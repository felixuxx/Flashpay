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
exchange-0001	2020-12-16 14:26:16.868017+01	grothoff	{}	{}
exchange-0002	2020-12-16 14:26:16.96935+01	grothoff	{}	{}
auditor-0001	2020-12-16 14:26:17.066251+01	grothoff	{}	{}
merchant-0001	2020-12-16 14:26:17.183748+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-12-16 14:26:25.032039+01	f	3a89dd14-aad1-4b0c-a43e-2780692117a5	11	1
2	TESTKUDOS:8	RYKZB0WW3W21DEJ70ZDAB65DHAHWBT94BE7D85SH92BWC7ASZBCG	2020-12-16 14:26:26.932622+01	f	b67bb385-1870-401a-abd7-1feec58a2dfa	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
ea1eda9b-2c8c-4b44-8fa6-5335ae9d7f3b	TESTKUDOS:8	t	t	f	RYKZB0WW3W21DEJ70ZDAB65DHAHWBT94BE7D85SH92BWC7ASZBCG	2	11
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
\\x84db6e6c138775a435a93222b251bf8c6fe8c48ac6f6f11d1fb1d01b99a5060f	TESTKUDOS Auditor	http://localhost:8083/	t	1608125183000000
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
1	pbkdf2_sha256$216000$UzKwmMEuxY4Y$qtCQCfp2ePo1O3GjTAUk9OSZl25yIxihPFByKQjt/4c=	\N	f	Bank				f	t	2020-12-16 14:26:17.608077+01
3	pbkdf2_sha256$216000$vxYxuNqJB1O3$LA/bjrKJPZYf+absVOIcBOCDKAjHVBp8VMfAnJgqoLY=	\N	f	Tor				f	t	2020-12-16 14:26:17.767263+01
4	pbkdf2_sha256$216000$llofgd2VsbV7$2j+t/GkJSgezH+p+VRNzDhaUrpKMGvWumRujjIYZOrw=	\N	f	GNUnet				f	t	2020-12-16 14:26:17.843414+01
5	pbkdf2_sha256$216000$7g2PB74XwyK4$Y3f0lwca4tzbpRIeccBXJCRqrr8jCk+g7EHKhQBpnTA=	\N	f	Taler				f	t	2020-12-16 14:26:17.919652+01
6	pbkdf2_sha256$216000$U7i1V6Pmurq1$04EXV6b4d32h61xBuaWVvFRyWlj8PJZWL7B5bPU0V6E=	\N	f	FSF				f	t	2020-12-16 14:26:17.994243+01
7	pbkdf2_sha256$216000$v88CUmpDWrlC$zKRklVvAzrg7ZTgWHU1KSwY3wPny4qzL/C2Puho0QLs=	\N	f	Tutorial				f	t	2020-12-16 14:26:18.07125+01
8	pbkdf2_sha256$216000$h0B4NpOutnre$xwJYOXQq3NRfH2OP6BMtbSCxIWx1FcwvfZ+G6b+Ze+0=	\N	f	Survey				f	t	2020-12-16 14:26:18.152538+01
9	pbkdf2_sha256$216000$f9kqOmrv0YUd$A/69w/zGC2sGejI79mxVscOl22jaVQCV9uEHS7osL7U=	\N	f	42				f	t	2020-12-16 14:26:18.609286+01
10	pbkdf2_sha256$216000$kPj1ovh6f3rk$CCqqwJsKKeMcu7Wyi7+Vy59QF/sQqFX639gv4mjaiyY=	\N	f	43				f	t	2020-12-16 14:26:19.08981+01
2	pbkdf2_sha256$216000$KQIXDuq9Krjw$bs00NRR5BSpFNfurWu16zfCJqK8TPG6PWhwIpbGB9yw=	\N	f	Exchange				f	t	2020-12-16 14:26:17.690798+01
11	pbkdf2_sha256$216000$CvoGfDf4w3Sd$55yE2MpnF8YDrTWX9rCB4ZH1YKqDM11azko4LwbIyXM=	\N	f	testuser-lhtoyOhh				f	t	2020-12-16 14:26:24.925886+01
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
1	\\xb947e342d12730a7af9113d8e65a7a7b90bf9d6f6925667e296de73bc22ee767e12f6ecfe8364b4c9b269a098aac04fb534290908f2443315bcec775b4980a42	\\x01400544d193676cbe78e426f9985d34e2c0549908aa4c9e63d6289e09670725e58ef051160343525ad0deb46609f94118f80f520a2f8afca7a7957efade300b
2	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\xa8b8a71c154a2b6c04caec447b031347d1c2585def0fd77a4d9e4672fcb70658540abd62caf1655411e5df3fdcfefa753a3e3c5a138c42682ad54ca3c10c7304
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x004466858dfb7971e87643b3366a4a4710d5d3f8b092dd04f7eb81cc8d633659abdd12bcebb2e4f435cd3b57229c00c1e4144ca525ff2fc776e7e7ad460727f8	\\x00800003cf6e779f2aef4ba9956da01b99a4c143bead7ec1a4884d6a57a29da6b818332f890c8dcfecca0577d06fb289ae5a3782256c02a8e8ad51bc65b782c9cb0242daeb04943e380f9b927ddd70bd5618cf273d693110e856c7532e05244bbff86266c9c52d169d7c3e8fa0c9cc0e5ab978aba26a9f8bc4ff98628a8ba088000063cb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x674bad8e9ebb660a53107e9b5e10fd888698fbd5d263adcb79124fa85c97a13ee70d8d45cd2b1de436f000cd06749de17cab0f3cb39b21da58e3fd849638fd02	1631096177000000	1631700977000000	1694772977000000	1789380977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x01c8dd6ff7f3c88fb3069f391c6b70f45bbf35673eaa528e938962df501e869521be2a63c8231c54443141b17b480d680415a0e185212300e1fdbd9f7a78e67e	\\x00800003acdbe9458b7e21f7e9b36896aa95538cdbedbde02dd2ec8916210edefb822d26e3bc1056f83bed41498e7747ea83c34152a96d827b0d0fdd8891d0de1092c495accf3803eb3c9be19e878e54cee6b156752d8d8f27914e3177d1967d4df83cfc4c063ec5f79ae73335976c289baa8551a8726a6b6e9416d4cfbc3da1f259f6a1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf7cf2cf2426e85434107d3c74566846d7ff03e1e42791b2386db91798cb88f7051c1553d3b623c6a214e0dd9d3988aeb196031e5a071de0f26c951abace54301	1636536677000000	1637141477000000	1700213477000000	1794821477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x04dce80724fb39f48c6b6f871967211e1d96576ba3e15da415c3a56242e2fde22c6699efd4e03cfa20405eb1421675326724d8f194bf78fa96a15ddaab6856da	\\x00800003ac5757f4a1e6d8ca8e5f30a3fb9380cfbab647449a44203e38d667e9c641ca0b3663005ab2f5e7940c19d08a39e80204981dcc6ea00e63112226b07a348c3fdae799196d44427333347cfe7c727c227e3ed33ece1dbf1c42db2d587cb987d216fe4843523df77d70f4c8505843678a908035a79988747f315fab744d78ea609d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x96e4f1d101c5ebf57d5688245be3be58240966abd69ce7f1a54b4f17a81e18750527605a69e7927c5aa605694f1c946ad9f84d6d86c3f8930308b7ea8f078d0b	1622028677000000	1622633477000000	1685705477000000	1780313477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0558e4a24275af41fc7b540497eec5c4a801da5221b4f2521f69c5991b2fe20830af41ef552deec42db2097b04b6be6fef9da166bf4aedab870dc6b6d50b6076	\\x008000039f7fe717c74e172902137c6d0aaca240380867a8ece532901d69f6d58892d98415c97bbe4c4d6cd32ff088291a415b5710343bc7517f78901b91099a2bf23aaa7a5450c1b93386be8587c5745b670cc3a3c10d70074c6484c5587c632527028233768ca94519d6db5b6d790541a5d68acf6eb62927ff15572ec96a4c30633287010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x776dbf37e2be346f12732325c1ffe34cf79e41c14d8dc701866f79e520e2c2c9db7622d19a4a22cc787b46cf10e3e01ca5570af6285b970736e0d2fe48cc3e0d	1612961177000000	1613565977000000	1676637977000000	1771245977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x055c46a4cb3d2bddb48a31ac3a368e8d24abfc76c065d6f0b4020f4348305d9918ab45e41818a8c48b04640e5c5227455b327d9c8731d444fe615d7a0cfc57a5	\\x00800003cabaef96e65422103389334faa273f097f8683d9d1e8e1794df4c9c08d16328f210d5c5a8f50de11eeb53d4f87953e69c2462499733cffbc1a28b36cb2b4b5c893ff72cae14840da46c3997fe882d3493bc22516267c73917d4e8f08c0e1da9ead60e93f2268190e2e7522c88b9df1479a24f0f0292261f56ec2621d326dd0b3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x23ee5e75dc504c50aba5f1fc7dea50c3311fd45c443cbdc69eb79ef5d9ed65a2cc67d87623adaae6f6620abfdd7e7a5712b4c53aeda421150faeb2244dcc0103	1638954677000000	1639559477000000	1702631477000000	1797239477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c486a2f4568b46a5f05156e814deb238282c4d01c94f659bc76ab1057d45b5911bc1543bb8a56ae61c22df2190ab5d54ad45da9fbd3f1377fdde2d6ab2a8879	\\x00800003b8cff63fb0a4e5b5c6a4b79b5019582b8baf37b27ec20afadb63f57e86f8c92a0cbef0db36b6fca7680e544c1fcf06e8fdcac9fa3d757dddd527f56c16a100765abd147a68ed04cc2281c7cc66813d0c389fdbd5648fa47de400a643f23a5a100a346f7d31400c6797378a31f3394c6c6645e4846df40b4f5e1e7216747b3f7d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5a020d0d6d0d9fe2033a57cd3cad45408fdc09b546f3e3539852be921845ad25935bf9e8ff97f6986395597f28b8b401079c7d6db3963234a0759ecea1eeef03	1628678177000000	1629282977000000	1692354977000000	1786962977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0db00cdb9841afb750e0d745bafd161fcd0944f3e906b7f77431cbdb2507f5d8c10603440b4e670eb74debbb6be7afceea8ab30f4f6b1fd986f88f038d22478c	\\x00800003ceb2226983fefd51beb9d260d56c77b3b82f7aacca6414502b14506974094cf48d7862e910068aba75159a7a27b20c53af5ce15ab7c12142e132c3578b42aae722fac787cd9ad81992f2cb10aa89a8e93349099436e2114f62288d169c8e2ccd2e895e1faddd1b856b143a107a25608a849f8a338dcdcedb271277b1f67b4363010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe2f8764b4bbf7a84bf2ceade58ab8d97cbde4e980f25aaa96df00645490eda8fef98fe4e1c0d18b67fd3ab5c8bf96508ad19acef6662fea71f6c127c1749cf0b	1638954677000000	1639559477000000	1702631477000000	1797239477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0ddc70a1437463c9561dfea5a210a98151130f9266dde46537caf342e9f4a8c45fb3ebd040dd2c8892ed05789b4bb76869e37e42e19276d8068e2d3e446dbac2	\\x00800003d2bb2c76040acc535cffc555ae0d4a164b030001c27cb55382ac8f1561557d377b5bc7acea6153d0c157479013bd9492861ccd2c0ef02a8407821d1cd9d7ff05bf88378c386469c20f30af1dd07c4510a0b9925483b625282dd81bc2dc1284854e447347e84b2d1c7179e37a84800b0f5ef125e5f8504899bf1e2da434017553010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x338b3046c792def265da2aa9ed59b86ea2c67e3de48679c334c851d431a0462dade79c4216aa656a03dd6d49b352da7e11cfcfbe112d0c879c9b681a0e5a220a	1624446677000000	1625051477000000	1688123477000000	1782731477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x15a88260fe665ee7d545afc7576a04c0c5461dcee0d3b24baaf2bc19128c7b1d01209c090a4c48dad5b5ddeb9fa39a5c105a8e7cd4273bd2d1c32424361d751f	\\x00800003c403654033ad5383bf4d05b22a0d6bfd4d18d321592d5370822fc9ab6dc4ee76f0a77a93260b8f14dcacffbed9901f80b764acb8772141549cecba7e4e56c464daf448b1bd9f3ffea4649f4ec128f696d5f142c35852ab5fe462b63e9fc5b2fb766b938148687f37a82d2f40b4a8c3806fd7fb0b1c07ec16db8f105296ea0367010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xcd4c5d1aa34065fb388bece60494ba9e61a49caef6b63f02975403d7ce3881a8a63ba3ef1cd59e0d954ab7f564cf35ff8d3f14e92161829ef7e711cbef20930e	1635327677000000	1635932477000000	1699004477000000	1793612477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x18acbd02fdaae76ee5cb43c2f3ed9ffe1db038c6e0fa3db225dd2eef1d2bbafdee7964dcad28b26f1f623ee2a52427675d26c4fac56b0269ebd3fb8e76d36831	\\x00800003ebfaaf157a9c441bd61f4bbd792bed24ac31de99888b7a317ec63f9e4e31371793c3c404fa7f9e13701db9376378487d0ebf7359028111f88592a7537bf2fc502c53cf9223cb085adc9dd07680d9d50457f2cd3ffa3d07b72addc525ed575f839935872590f9fe65501ac9417fb693987e3c6b478ebeabc318df3b4712cb4e71010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x569fe1e0620b33c54022f7cb2dddffb43294e908af685109abc204b8d62c609aeb9be1899d8b2f8b7a8c127842b583c91f18ad748e7b95d0821ac31cdc1d4506	1620215177000000	1620819977000000	1683891977000000	1778499977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ae0e270277c2dc5f66e2e0693f740d3d542b14a5ce84478057214ed3aabf0ca6ad33bc1a1b202145d4f9ab4377ae1203665f8e4fbd5cd8f13769dd8625e29ea	\\x00800003b4bdc6e9037c14f5bcc8c9a1b5733615792a7908e687fafec62a1310720c51fbb33fc1b72b5b23e935e4d31681f9646ae6f09c01e62c2b9bb45cb0fbf6c26408dee9443e1b382e24fc623ee1fc243d9b8924237b1ee2842fa3aa0a5a44aaf188d3f9236df8b567ddd3add803cc34614c204654482ca865aaf970ff98297dea43010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x18ac36dfe9ce015be82140be0f4c8b6ce25043396f94aca256660302b65ffc7ab437b47e8ac1cae84c923e281bb71378ef476e41a135814034e1ed138cdcd405	1634723177000000	1635327977000000	1698399977000000	1793007977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1f10d07870f573b8b245886ef83a4631ede664d10e605da03646e91a68ce1bba7385a59189e87f0f2470dba1af7470422d7eeb63256b0c21dfb0a53210470fe6	\\x00800003aabd8aa20c8b0c1e0e8c5722bfad489f519e28bba3343d0e2ad2fd4295c89fe43e7c75853e34326081d9510ae3cca10bb92e785350d247b54ff758d9ab40701e7fc3aa15eddd859ddaf5ed1e1fffeecf731ed3b275485e70f65d59ac56d46693d3aebe9ad030dec23a9df14da563ce6cf3fd5bf4b5a7c3676de11cbbd3788bdf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x005b1cd44ed56d1e9a384cbbc8906672509c000d466600c8235a4a45f075f4daacdefa94395aefcf92d640a96a68f1c1a685456df838829b60b9e9a8ffb45f08	1617797177000000	1618401977000000	1681473977000000	1776081977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x225cbcef8262821983dbe3e7667af3de9cff07d90fdca1dc790482f75a197713fe101d8ea51a042a42cf9677fbbe04bb58fd773d9e53f6d6c7ea394e1d506525	\\x00800003ed431609a03a70ebcac8635081d0fd54732dd93425b11d03dd539c1d258449b180a47495f527d2732dfcb87c430808520b982308a14bb90155e7004290e7db7e647a50e0106bc3d00185733f869a3078135a752cc07a249d72daa299e79d1b659ba9fea436114a48d2fe2f52a8234aeab870cf95ed9edba97936b2561109454b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x4c4e2a87d117b802dc07107fa9501cd420f50e6f9f31afea92d77e2b3500056414fcbd045b71edb28097aee73d75fcee8328531643d33877d2188b5f056c0108	1634118677000000	1634723477000000	1697795477000000	1792403477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22dcf67fff8e06b23a4e43ff1233555e04760c0e54bf2f90d1e833bb3c27db0da8d9e6bb7681184c6e3c531df3bb2f419cdfaf6471f9aad188c3ef45a8686834	\\x00800003c968caaf3cf9c6432dae08e5179d0c56eb318f68d96218248cb930fff2eee868441884ec40bc777bacf4e3c19afe839f6526e15ffc99bd85bde650f93b3eadd0ebdc780ecd701a58bed07bcbeba000024145470b38c5fe4acdcfef5992880a011fb10d33444c1add98e6d512520ae61360bc202347ed0133237ca116c6f6fb79010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd431a35436ede133f3496c882dc1bc34e43cc489b74fba149ec5c21ae687b399222629008955c364f755e9a80df0f4e500021099fb564ab63d67109371f3680a	1628073677000000	1628678477000000	1691750477000000	1786358477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22d8202c268b3c7827553b17ff77bd528d35b4285a41bee8d6ee3846f6e43a651756110fe9ad480c376de2c39dac6e648063fef4dd8bd5542c8df6b425988907	\\x00800003e61c00838a17e254cd5d6e381b55ddcc0e19af814e74843ba3933331ba840a9194b22ff53f6df223b652cdde3ac445bd11f088e9bdac22893c044254f52ca1646c7d4d0fabf7e107d050c05d947a3288007b3bd736c2da7a5b3fd1e939da1f5e84724a5727848b473a8afbdcc429346e55a3d25fb1bb1fb2e40a10879f45e7cd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1f0c1fadca0f476b17631f4177b4b0238162ba7b1ceca2fd620b1d014f0472435e3d9b53dff9eaae991a2265c9b58c99ee5e44e9c94b76d9b8dd747680e1ad03	1611147677000000	1611752477000000	1674824477000000	1769432477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23bc15dcb4bc4d1b18e45a516b4a9f7649f351692423d6c46b15f8ea78ae99af0d5b0f3ea833f692f042a55a0ae1a1bd2e7db00dec51aa8e5ff8ff63c2db6474	\\x00800003c4b83848d130489b7a2140efc2751dc6c8bd78dda5eaec520fb0d52e44605fb97af21b9cc32d24959714f01c55f4849282fa73b13dd01b6ea7b7a5f452eebc3f131e4d84cf0e1f1282b280096828a359435731190b2f3098b1f89c4919fd0ebf11f5545680cf3e8a3dea4acf0bf23c056ca77d8d8b62c55bf4b7bbf930dea1d5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xed0b8f86ccafa13d878c2ef1359ab9b8f63c22f2a1190e5222c507bf109aa70148c64e092f2ffb928bc648ea9e8e8992153d18c09f698918d72387cd8d206f0b	1638350177000000	1638954977000000	1702026977000000	1796634977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23484a62049f489654f1586d1a09bf388011c2a784ae2118c50c1903e05459721a53733f2b29effbbdc3c510c2b0c8a6a0dd047fc6003f654c8ff90274415ce6	\\x00800003d3560a4be5ab177bd91290733243d429380cb29002925c08e7f47b346f983d1806da19936d371bc248b78ad134b01d784355a05f83a882dcde21afe6877fd6d4a6c81848f93339935d7ccf093e2f354d3cbf95849a3c02184ac8d0b25d037ab091c0dc93dc79aaf0d30007b721917a16ce4828521b50a523b6a63e9a1a06225b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa98edf08b0a14726f2935533c007b96d4b6f9a0545b64e7a75173ed318c08001e02f86d20a5ca24846b8723a723e5ec3f52eb618cc04de2b971362f099fa6d0d	1614170177000000	1614774977000000	1677846977000000	1772454977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24585d05c128d9cae2854b719cad0402c25502932c6b7f0fe942a2a53f9f78cc8a5f5de36c8778eec54f58aec1a29c15d0c81d5783d927528575f7ef40cfbb60	\\x00800003f8b769751d2104e3d972c2015cf86cf2389cee474da3ea3a20d7139e572bde642bccdd87e00bcfbb0c26770b11e2d8e8fa327472c355010946cc0395de33cbcfad2a2332cbe54d5af43d12bf67c8673bde71724f99bcc4ded2f97b11e0d90c07498725628a438c4774aa645bfeaf9127b2f260508d540663009f74b6778f73a1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc5102aff321008a6ef6e130ad735d33ba6c5a58de53b4081603f2e696747b004296d7b55674249cf44039f7483ed46a46718c69ae1a8463b901e6aa4ff381a03	1620819677000000	1621424477000000	1684496477000000	1779104477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x257c6849497f0163d614c5d337ad4dad1c449f7ab40a1991f81e68d6a0a6d7630db599bc9cf9e45c472458b790158f511ad7d353b74864fc74940fa06598b8dd	\\x00800003a0839e91a4772b55b6541d95a73d7650268c2a0d1bb994d7c17d8eb1487c1f2e7b290a627791cda491cfefe76b7ac1aa2ecd8a4001f258acae0544422f8cac38b3d8093bd2c29a30ba9434be2ea940d379249a6b061e1c7c4dab4309b29f0f09260d772dcedf16e5e09d6d40693c6602a08f06c8fd21e4b712584a96a2df49c1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf06440d54884e6a0c5ceecc65e25244a7cfcac21e1d356e4519ddf32e80a38bc06680ca1d167dd47c06a52891b135426fbcd7b64030a04bfb1a509a5432dcd0b	1616588177000000	1617192977000000	1680264977000000	1774872977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x279c1da99b107514e593e87a239eced59f9d49bddf70eb23b2fbe8a3815e82fd5491c571bf7282fb334fdd41dd39579d767cf97e71c0f2729b9101d71e859655	\\x00800003c36459c47b7761100439bd0ad2d61319cbd9b91e79f75d02b0933a192024f31123985ec4e06b785e71aeb294b11ce97c6ff80c590d5d0aed9a0a4b8e8f9e65986f62f991557175a5c907bb087e80fea13fe093f16bd2e0083d6c9ce983fad25e282d14312eb70ed1add8185a3991ccf40a6c5ee071f66fb0a7f1e6e6717e2b31010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x479977625c01cb7a8d3e671525c8fad514b1b02fc0d2233f04a2e2f6df050ca6e4503caea2f2efe67722e6b4c279de5da5d074e298e9d338fbbf6c51346ba00b	1635932177000000	1636536977000000	1699608977000000	1794216977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x29f0d69a5a58e5421cf7ee04714edda7d259cd41b45c68dd9096fd87c31a63c9eb8ae979d9eddc675003395d7ab65b061e171882ab8f297e42a45cf2decb6193	\\x00800003b4c732a77070616547d64e1e7d77974307b9f6727bfdecd940a4eefc6e36af2c0506d8d3051783bf37ecc4531a71857acecf2d61ba1f130a822b06c1a3d6c34d1be40273b8e594bb0a34ba02622696339d0d8b9f36b2252849655114a4b5042e0afa562925a6d80d4b964f7d1cf5172420d9b343fe4cb9fdb6c226060b7952bd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1d495aba0d505867187941046298ba6dbb829b8f514629680da520be7ac0567c287f93370b3d0b9e5238c868ea89d9ad69f618b268367c02a4277642a1785502	1623237677000000	1623842477000000	1686914477000000	1781522477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2b5496ec2e501d73ed6f1c9b3df32540869c4f39571fa1f9cff8062cd18490cac239cf71c5e1a0391d18d9ba966d6b1ae4a274305af951b956b1ac6c7c90046a	\\x00800003db29cdd82742eedaacd4668e3e816d82e62677ac2396a42109c8eeb6bb7de04d14f356b97f7a5ef0d4b2a95051525ae61fff1081a176b606fa96407cd278eeea9e724783d8d4aa931a18386fdeca18e3e06308ed60a51726bdb2fdd9860e993c8368bfbe5dfa997529cdba3b50f46288b432bf6ef82a7e37099e6f916d747635010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x50f1c8a6fd55de6b851c37bb4f120618e0207811f96530d2d29ffd3d24514f84fb7e0a1a0546b9589f159bf71ec2817e84da50471b177796e84e1c286ba45d02	1632909677000000	1633514477000000	1696586477000000	1791194477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f0c52ec7b546e2a24f66e9a4827b132426c67451164af20108225903fa5027cc728bd2c192ea120d3e3719a2654d0dd1e2f61de845e7434f003146f43860d79	\\x00800003e4df01a6d43fb44608b259ea9bd4fd2d874628e1e78313634204d41c091b2cf99d8dc94681bf1e1cbd256ac3ea979bf94a325a53c32603957e13c8a87583565ed48bb1a404c0a990b903e9a96f19cc861eafb6730d7e9bd48f97b9fcda45ee31da04598c6387480cf4934ae507f65e50073a63ca77732d178e408a554b842df7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc55de2741d7ff3ef8d96c0e003d9da1632fd30330d37543d2da4097b11b66d41555fe8afd28d8bf994a3afd03388dfafd97434e55f8cc6b6a1a63c047844e509	1635327677000000	1635932477000000	1699004477000000	1793612477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x307453af9dc0eaa35b253bb7b04e275b235529dd00e155d1312d351ddc6da3fbce2fb885f41d57617ed82df501b461d67b4ef80ae91ad55ec3b03feca500be41	\\x00800003c4e70df95321bf5355b45fd73709508af7b467b43d0db3d4eed5d8cc09fe3cfe1bfa85d8fd4d47976dd17a063dcc7690fdc2034377d58e2e70a8e6478ad7574ffdc1118dbe8bcea4fe845b0f916faab75f518a696bdfcdaa209c1fe2d98be70b882322aa17d1685276eec813966b237ec7455bcda43c00ef2a6ce9ba32314b49010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0ecb9a4650e88dcfc73e2f6ad6cd2258bdac299af084ac952f1092cc8f7f9c3edd98603831f689e925a377663286f4f22ae5d0040a28f70dcdf6c901bc1d280d	1613565677000000	1614170477000000	1677242477000000	1771850477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x31d8cbf6d188ccdde606598ebcc312327a18c03e6a27f25c2d0b75d05f5944eed79d994c22cb31ec411072373d2a7b00b2b784f99508f860a80ba30334f9efa4	\\x00800003db83a378378dc83cd7920a2c4569167892dc13309e6b5290f69892863433547c0953844b06a232f5ccd594bfcadd07073db0d623c7c55e8b21ff7e0b233be8ae1e67dfd76efae6970eca0d7cd6dd163fc47fc9cfd1355e0a0543a1a6c47ad922f954528bcf12d01f5a87d6f148a7907434d50b61e098fe827c6ee1fbb5ce2089010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x81d8595f9f3b7725ff5aafb813c8b36e1b2dc8e77c72f9ff47f8101f1b2e13edd6c14e2a3d84e88c87e8ae6c6d610afa207273634ec3e6b884684df3290d4d06	1630491677000000	1631096477000000	1694168477000000	1788776477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32603396f16ca754d000bcfe3cb583ef0ccc59699b49472a71c9cc11749728f674cac1847a3223f231d96cb837f02bb3b560cb1e40c3c34f71728920c4d6ac80	\\x008000039090398369f46329492c273bda361ad5ab25507743be5e6080e8e40d14fe11ac19a2e40446c8cd0ec952b3f7d0691f3f9b16eae0654f2d033908a8cad4815a8e3fde73af5d769d8de64633a21c878096325c5a1aaef126dcc70bda54e4d6ceea15d7b21b45a97fb767b2c998e9be2bb84a4a7ff3a525245a1f38c24babf2abe3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xea805a4cba6ea82b009656d12b22490db343cc4f82163601445de5a43b522c15ec7e09dc111f4525c06526d7edef9f9efa462db74bb4ac258ad961a019747102	1616588177000000	1617192977000000	1680264977000000	1774872977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3594a6caa6caa5b3ff6104952c92629aa8fe70faf39ac15aceeeddf7df37eb1e4cb613644a450b3b1be293768ab1ceffae77b748bc69b97f5ce82e4e8da21855	\\x008000039b966b56e6fd1128cab639a9930b2ee246dedc7f49b8aa0c34aed085e370c95360e1f589d329016e485de8345f0bb170f0a722312ad777a00f643de618da2a7a837dff5d8c19dff14894a3797d64c2c68f20239ed774abb24aae1ce800bf4f753632171ab776a7b27b1cc8c7aa7c6001a3149accdc8dece80a970d17356c6bcb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x350fa2c3a8d4445fb64fc3bdff4b40b0bb43898ceb96ea0aca733bee733b2ab40c9fca7e96b078f7669e2e208fc8261c4155bc896f9262da868aeb0e5ffa6309	1635327677000000	1635932477000000	1699004477000000	1793612477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x355c45994619b32a046cfef92d97b16dd1c2162d6b34aff483e50d4f899321ca94eee1f1ea58e200ef370d2f1e5941d7036555e966669a2ea5744d2a29cb9fe5	\\x00800003c91290ba20999bcf5242adbbb39cfd1d5ceeccd9b7517bd2cc5358da1e419874c3809d28cbdbb97370e263faee2c3d8f3d2d21c25f0652926e350e1fb71bea7818227240f2c5c161290fd4ea6d7a0565f81e8bbcd4822742e8e90d487426949304a6b4896647a30e6c8bab1f675aaf36a20ffd3027e95a6761a85cae12f78913010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbd43f5c7bfefa35cf82650c5714794bf06ee3efe85ccd2f057397344053fd89166ea9a4d2d053b69fb45abc2d4511b0e1f63a208f81a810eb09c9f132ce99505	1611147677000000	1611752477000000	1674824477000000	1769432477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x38e079d63440c2a21e9442477729d8eb3ee878ca27809d9113c992d20ba40ae4ec1c50b4a53d03333e00b8cbc6ab81e8013bb6d73c7d816662ec65f1ad43eaea	\\x00800003d7aec2579e55ce68b2f9f2cd3b67ba5b96c63f5ee40d3cc10a7cfc7e3f3b7ccae4e7e554b84892ce060a6609e4ae215b7cd0a09f68cbbe42dd3d872d8d6a1aadaf99a9d4f96b1a8e9227d0faccb48d6e6ae5236cd2a5fa6bb368870a6963c31197c6deab8da0e6e2e19ebfd700f73955b1d386196c27232e10fe301d34a9042d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x05bb655c558a4bb762f26c018b134938eb71928c409f6d2971a36451ce2ce3efcfb377a4d1a4c5d8d7f11e707317a49efbb07cda3e7ef3120079e07d5971d90f	1615983677000000	1616588477000000	1679660477000000	1774268477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4350219b3bc0577958a7ad78a606cc61795a8a43cbf3d6b7d427e7748d340e73762a42033a734855cda32363488e838903d4a5dec89e02fdd30c4209cedd2eff	\\x008000039957d1677ddac3b6fada74e36fbef0e601516106fa871b984232910881a0310526a45f95b66b2762b5a23f52cb4528b28fbc33c38d796aff0b07d24f6c38f2ec19c14096a73c01e183c4276ba3b42e70658b95401e71aa309346b0f8d0e4961e6d1466c9778700a3f09e9f9dd5e9a704d63a9f969b9be77be3c6ccd9b68ffc61010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x00cefc98f15b29b759f7563fe543820dfb1ce8e7403d79695bb6e756fe8f033182ea797fbf92db18db87db45b691f2ec33465e86650db1e4a1a521b458bbef05	1611752177000000	1612356977000000	1675428977000000	1770036977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4d4837913b200a0679cdb943ac34d919ca8de5ea766defcc035daef8ff6c8d55ba78ce43b59b5de5a1b52dd2d1d34b4cfad57a335b88c4f347c35de7f5754f59	\\x00800003bbdc055b86631ed168afad6dd70f5113312e9c896710db7fa02c22e0d51dc63853721b5816905ddd2ec19f7026439634eb8fbc58d5f5038f8323d74f2dc8e1207e5ad14228461f7b56962be70ab403040c5124e8087ee754c90d68750731a75fc1db18a78212158afcb4f3a54efca71d9224faeb17e0e39de784c1051ba8069b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x963d961c1559b197779d6852623ea624fbc396da3a5204a52e14c25377e213d012fcda8d2ab17ccb5ea002eea1eb518be115993cd2d77d7c6806df81c3352306	1609334177000000	1609938977000000	1673010977000000	1767618977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50745106068ce112825c85b9962be292ec2729774deda6dd2c22243258f793960dabb9fd54c290b11ab97b7f6fdbcdea8b9179717b09ab3bd4b23e0122c5638a	\\x00800003d5e7f58435e612c949251d00b7c7198fdc5a7cb1a6d9e76cb41fcd9d8025944accf829011450b2a728923a255f7446981a6736ebefebce242aaa6f8c837f55e96383e5310ec22293bc5ea41a8b492395dd55105971ea78ca748c44cdc990bc5569185f22573601c748f48fe0f3236794a8f709467298ebe4f7374fa08d752703010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe949534b742a94456667737e176dd7910f1399f652f411927ebb50dac10c806d52ea3b10bc1042070fcb050b397934aaea4f60724bd0b48c007a76adf903bd0f	1626864677000000	1627469477000000	1690541477000000	1785149477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x57444a612a221813f0ae1df5b21147b676a2337578a47b42ecc434b6a8e41f554b211b08fe86e86b60e99bcd66cf3a26a31239b42beb661b1360b16aee4610cf	\\x008000039e055f9a12e698a24069fe9d74e6bc06b65ab61c596c31958a8139947117aec00392570582ae9b14de473b8dec6d438b998ad25bff07f17f28951b7a9d35b62cd7b84b18e9ff5111314228a651cb6e99c050459bb81ccd940d4e98314bec2bc2a226c41e5a27ed92dda058fea8a283f9095688e96682695ca56ab2cbb42a13c1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x565983feeab250ec494e4bea406b1d6c2b658c1f0c1ab68ce43efb93aaed54c211478a7f7dfb9b7fb32a3b74663c5aed39dc1c8d716f0ebc2dea3310a766000d	1637141177000000	1637745977000000	1700817977000000	1795425977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5754f0d3fce11baef5b59f2e5c75e4c7249badeb629adb033d08972b01c4e0e029803bd8f1f19b58708ce76dc32ac291cef3efcd2523ce75b864da7f4fa9c4ee	\\x00800003b47c82c66a0e86fb3844acfee9156f25ce294ff8124d1e1a80a39bab29e3fa1d3d93661fb790943a30293994371d2dd9b898f9ea39c3be378864ad88887514958e53e3bce7c300de3546da60330d3bf42e91a40b0c3792dc864ef1682228ec46a3b2e593794acb269388e239a9e1aecf070ab98cf5ecea18ab09cc62f8257181010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb42afe9d46d0b8aca674cc49a2a7d57dc402564cea84b34a8e1b0182252e85632f5f21aff2aa60128e5f4892da2de23387862552235735dedc8f3a37a45bc00a	1626260177000000	1626864977000000	1689936977000000	1784544977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x59f485e6509920b02351231a0d3070c447591f2a01279a913abc6c87adc6ec4b165b6c1215f0b3b8d945d59235a1da425e6c92c3654bc5b01d4e8b308791c8ff	\\x00800003a724cab68f60777bb86c336949ecdf9a01ed7fef271dbe45f03d23d89f39ff170420e7828d467dd1a33cbe9d403944bdb0edd0375fb8270c42fe56a038e83f0976d9445e49f186632fe2933ee47ec2234ca61403d5ba419d2c69721e9c31b15f5f364efe2d25e899246e743cb8a1ad02545272f9763eab98afeee57c0934ddfb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x784577a5f46f1c117fc0a1864a34cd1582589022808611b738ed5bbbc349bad96e77e0a22073ff4533bbff73b6e77233aa2b6562929c0ddbf4e44a3b4f919f0e	1622633177000000	1623237977000000	1686309977000000	1780917977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a50507798f4ac78b872d07f3507caf653cd7429b110da716eca2554cf3e0bb17808ac62d743f41eefaf1ec5b395e5ce40e949566891cf387a160bf3177108ab	\\x00800003ae7c314a47bd6b1e7306c98cf7c0ec867d2a67d5c7a128d301c42cc4ad1d4f9dada719171e861a43ccf14bea6ae5f2f4fed3b53f9edf5aa60e612689094c0fd2552bc1aaf1e8f18f5e51d59de8fd5ca23b6f8916cdd6ef1f1b8b3b35cc8bd7c374b58899bf029a0f9f917e1ee8a5aa7d3b93c7fe147b9e4611b9803c34b530d9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1aef3fe5d21ec061721c7bd35af50e25b0a37d1b8f1210a6b3be3b1b2cc7e4e9f7bf65490b1980c0b6b24735016df8e2f455469120c48c8e39eb3874410f0809	1631096177000000	1631700977000000	1694772977000000	1789380977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x635072973417a3e7115d455da894940aec9a9c1d3bb51fe6db0d8bf9d265bbcecefd209411ffeaa8580276e60c7a9e8f5df3d36a159ed6abf6f200919b390757	\\x00800003b6cbbebdc20d0c00fc6aabcb56bda070b43d95309c861f78b19decc55a47f7f13c828d053aa803be1d67c130de728ce13da1b3ed07a3b13eb58fd8ee3750188a9e21c7d031785f8639720f1f6768bd11a22b191a18ca476f9b55a7f1c3d3e7ccc2c887cada7e078ccf72d5d87eb559311110c062836b2b42315b875fa4ade323010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0b3afd06f8ed7ab8d6df8d66a599f77db34924a4fce50d32f1e6d05031dafeba27d7360b6306bdc5d8fba65c29769a6a093a695fbb01a87eadcdb4b3ea8c570b	1632305177000000	1632909977000000	1695981977000000	1790589977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x68b41a429bd54385a4a90332a346a5b7d27194d4f996f0c91894cee76c84848b35d47efa671b1b719ce97b2b8812affa86946c2c1fb57c924cdd6935490ae4c0	\\x00800003c4a48e530f8921607107b3219b751b1240c09b7bbf1b2fc722f9b0f12eba2c2f66fb12443c64c7387a72dbd4c56d268871c57c052e2bd812b882b75a5292837cc6aa3e95c7e7b84dfae8661e2b0971d321873e3f3c50cc0a3cd4a3413b0936c2fded3db98c15a9dde4293365e00564a23a1af12bfc6aea987ff80bc7466e3b69010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf38526d95445403e6f9f6a8714ec94c883ee50a5bcebf1c7f6d01a2f317357f330d231e90f5ddba0d40c32e34af1bcc79c945dcac8f135fe7ac8a11756b80a07	1614170177000000	1614774977000000	1677846977000000	1772454977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ab86191adeaae89ecd5f7cbdb3bbb96a3b541970ccc288423b3ab2d49a11521403b1d4ef5308ab843616148f0aae6b8a7487920a826afaf10897bc2b70ef897	\\x00800003c1ba0330914a549bdc24dfec425827db9a58bebb1d639c86b20831feddf21484248ecf33091d72cd6b2f5707d0abfbfaa47b6d06ce83f3a301a96131e12032c36caae25b7227db3eb30c73197727769f3a30949eadb10b8ca8166542a63942251e38acbf41fa5f5741ee195e08f9c0fe187e9c5f086a608efeefd79d1b9c6df9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x061f5759bcddc4827d2850dab592b8633e0f67f671d31232ddb7981a2c4a6882a5da65cbe0d560ca22aede580de03e6efefbea2b2e6e0fa1a537c8f4acefbb0e	1632305177000000	1632909977000000	1695981977000000	1790589977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c80dfc2bfc35245290ef4e5452df8645fc0b9e284e11f00b084322c7bb59befb7a01316b0d7919b57e522d869b166f726beda7e087febec37a89fd57ffbe558	\\x00800003c8cd09836d71f0a2688f6f7a5fea7b83047b667be040acd6e8027538ec1b49efa85ccf8f4ade7416062de6bf31aabb6c2b4e3896e397b28d0b4bd6bdb6e648add1764527487110958abd62d25839b755aaf6d0191dfa907f35ee8edb43518ae66d14dd954f154699b2bff7824943569c4ce615dccc7188a3a8ea18e2cb6f6e9f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x4e0ec908829d846a9e8e547144dcd3088e132e0b7fffa1cfa29f1ec691d30afd9fe999c322d832902911a4b442ddfec2bd8cea423eb779ab3558f8071c82ff06	1637745677000000	1638350477000000	1701422477000000	1796030477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c186c0b3c251c2729e6eadb9e2f3c3fa5d5a41d7b986429e8e08e5e792b3199dea787ba1b5d9124c71ff0277e0c92cac06d3aee7d9a88cc43c29345be1a75a1	\\x0080000391b08946c9b98047fb4ce3e576d006233d9bfc8d9c91733600b625b9511411e64840116de2e816289156138d1265d69133198dbe56eced975f54bd088e420ea9fcb6605bd711a99a101eee7cc1ef66d1042deb8e99672a4c6423ac0000febfdae98939544d43a794c817a0bd18a8d46722c69c09316ce000778e20d8dbfa7ba3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x80b7081b990d96cc45cba1a3f5bf02e8b42a1c4d840e8341984937b10440232b6ea0a5152b49adca6bd167d4c723cd6cb458d149c0fd6d41b5bafa4642191208	1639559177000000	1640163977000000	1703235977000000	1797843977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c04a8998ca9401575dbb464703ef22d9fee50479b9a6c8cbb3326a5f6bb4ddfdead9785353add93df86e86c9245be8f48c1dc7aea4bc8955b2fb3686df26c19	\\x00800003c1a28139deb782e744d4ac64eef65d1c9179bb0e1bb6cd16abfb2458c5ec6c533aab7b0909542feb8e47d3a02b61057129a7a4b0b07f91d6f0314444012b396506d2726bb11ff9d3198398485292943d4fe7b3cbb8ff158cb0a465055af0e022e1135cc22eb3f7f3316d7d8889cf8e340372f5395d3ec2f759bb2c6e1dd0c23d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x687479374a99298753e95783ea10714be92d161ade56911cbd298526376123461068f8159dbaef87eabd5c6adff99534b560fd51b2b2684b9a7c5761d2ddea0d	1614774677000000	1615379477000000	1678451477000000	1773059477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c44a2b360516f8feef46a3045c3190e5686b16cdd5ba89e5577b247ce7c084a2305c36fffba144860256280623edc3a15fe36501083ce8ecfa9b9edef8ea2e8	\\x00800003bb348ceb836d137d3f43285863751c6414c6edea9cc6c9330e3eefc5e20313d12d1f4e7ff72c70f004c116f06b3dacd2ee6aba3641ce4ec2dcaed8af7c9ffe4e1f9a4678c6e8da22d199753e616c21354a83f06667f18dbd4fca119fb6140a71c21fa686db8de31118f9fce6346fb7a3ba14e428e451a445c68cd18e05ce284d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x56b56e72ac2d9219fe0d8b518a978aaa1c61b1c89d14da96bfaea1913c247520f069f8fdada0b2073922998393f1d80c70c9a4d9c65ccbeb965c19959e31fc01	1611752177000000	1612356977000000	1675428977000000	1770036977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6ddc2ae0109fac2d3fa1eea93a090afd7a30a5130a70db2f0c467b67469ee24695c953953ef32cecf7831e27f549d91a6723bcfaf50bf306db494321d37db52a	\\x00800003d32494f135a14e39d349c2f49eb734f1f73f74c96ef6ad9ae012f164402c26337c6ac8fdc6baee1f3a54096c2bb7d5f1895ccb9fba14794e6355f3c632e8b0cbc88bafbd65fcb1d0163ccda8be27dd730a04840598d7324559509b81bc6add5d97537c5b059fc456097807eed0d13dfe4ad967d6dd4658d848a4937694f495e9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3938a0c379a374e672e07134c9c3330aa2806f4c70ebeca07ad5cc82f6dcfcc0417811d2adeb0889a9082bc398b2e9bd1f471fd7b383566a040262b318b00c02	1612961177000000	1613565977000000	1676637977000000	1771245977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x723c939172268ae9e942c6df9f36a7638823f640f11527cd7ec0f1404f6eb7b1e46edf3903c69cba93460bbe94464eb3f65db9369a5e87febc3f5d274cc78a39	\\x00800003b371216680238b192978aaf0a591115f4eaa5aafc711d760fa13adca16c29de3edf6131480b4c566b88720b80ad6cff43af34807d93f6ac577e3329db91264e44649e1428e9b0e1a235f7fb9d1f65a8d6283d13e8321fcfda0a61e08635bbb6a6357ee2b31a9595a2694769c02a5c9b12e0273fbb8c802496bc0757646d61c81010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe27b8f7cb5a909ca5e328fd2fce78f575e03d650ffc5d0a2e5a43fa3651ec3b3c412fda6bbbccdf7013ae75c1b1e06a1eb3907cf4fa4c278ba80c4f7dde1a40d	1619006177000000	1619610977000000	1682682977000000	1777290977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x77704f4255092f11eff269af4d84645bd2cd2b4cdb848e7a29e1bbec87edb525f5543ba14e693a39881b68ba0434d74f01bd70da15e29ac6b2b239ef27927e45	\\x00800003d065c959c5e59b76fa82f7c4bcd23188359510776d26edd04115d680f5f6ca9811cefb5b00e2f58999f6429a9ec28e8d21c46082bd04cac0540337aec6987a65d3aad79e46f9b4ed4a0158684fd2c2a955bb47b137a55587ac8480e3e6896de527a3e127d40e54362d94af2619aa3de62c6fad8fb1e30dc6ff26a8b7e494a101010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2c691200ecfe3679c140913a0c8ffd0fd2e9ad8715391810823c507832350cec7f00907e4e43a2d1fa8addae5a25f10cadcd1766086a404911ebdc9788b76804	1614774677000000	1615379477000000	1678451477000000	1773059477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x78549043dbc64b1b179d1c8af0d5d7bb8b004f858bf3944db4e00db9d238fe9e5a819062e408ca5033f327844e56d5b979396dd26dba502d52359d622fe6a1b9	\\x00800003ba6f9171df338b9c636a19d0743c67b7dde1aeee3ce781996dd9f38d8f11963763059474bf660db18e301c51c6d065b30c0a5cd57a464acb789e2b329571b198e76048aed15a40e314f77113644a62604a4cb3dab037cfe2654f815f77321fc223d73ea35ac421b43dd48d6accd89ab281c19c26b8967c0697b2c26272be2067010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x21532f335bded1ffeb9ed70eaa7aa593253b9226b768d1df1b5095518aaeb4b09f8a47961590212b3b1ce6bdb40a0dd6cd08ceca87e242ca123cf59189a58e02	1611147677000000	1611752477000000	1674824477000000	1769432477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x78985609f93cab19b8a716a5f690bf9fe030a824b3c5fd507c3aa02480fc8b4a100ede528002b169d74ccfa79df516179ccc544c04425afd8f655ab17d362f41	\\x00800003d392b528fbbdb5d41798d3fe4ffe2df49f567a7c8fcee3c64228dcf92199d2d9d6d519510ab6fa9b3a0615aebd6460708a409ad1840cfb41df8e02e4f11ea0d593c2395e29d57f619db682b0d4ed2188703c2c3e5ac1fea7d17d54b062fbb8dcc22781cdd87dc0cbb75297759a1b7916b1a56d8c8cb0bf9a032f40295e15991d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x60b31603eac0991728cc37dbb85af30b552e3b7ea06dc2f065f4774d164341e616f7f982bd159484597136bc6f525c4e5275bb8131ce24c9a88ce203ab7cb00d	1634118677000000	1634723477000000	1697795477000000	1792403477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a108ff6fc53663f2106f8a5ad55d00cd3983e8f087f9ecb73664f691acb47fdf1e4700634da1dd4e3978ef58a24305d335a49b9ac16c4054b46d50d08ffeed3	\\x00800003bda7e1e87f8adfd37cabfa3a07a3069463130ae88c2066a6e2dea0725a7c8a18c032f96c28b6e70f984bc5a942023eded82cf0a488425b2db65b49a74fe54c4b725c1b60cbfda68c218898bf34019e2c77927cd65edf04f91452cd9b9edbdc72aecf48d23ab8c885d9ced9b7d8bbd9072388408b9bbbbc9d1991debbc6cbe0c9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbd76baf32faf210bd2a38c38ed2f024aa40a3c83de794b550793e6b381c38cb41cbcd99b21978a1126d3a80d39f20f7fe229a50fd78750cae0213b7151b9bb0a	1630491677000000	1631096477000000	1694168477000000	1788776477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7ebc019764121de2ade82c9f5c8da223186565643524761025d57dcebcfeaa408d18b72355d36efb0b7582d78d3c0a0fb4ad4371c1d6d9ac8ad7ede42d05293a	\\x00800003b8ec01651c8f49d8028898bce6c804646790c6ca0715e076b89797aaec84a351e7bdd644169c1956d3b939f50dbcf1eb4d941356e40064561b4ebe27795af0104cd96792d60e1a31d63ef47e8e5d6f5845e5b805fd649208d8be2d92907e01ec76a03603df22eda7c83afaeede34e669b6f914623ba5f00f8f5f455eb62e031d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x69820fdeb11654db78f53713481a1eadb48de0b8ef4154f4bfb9c52431b2125770510afb7b8fb05431e7e32dc786d97f6bee95533ae88b6e6949fbc3a4f3760f	1624446677000000	1625051477000000	1688123477000000	1782731477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7fece7334bce9e996b8b2d7ba128585a95efbe02ed79ff049dcf815d6293b817d01eb99e67874083e3a1f682ac3565e91bcc01ba79d001dbfa4814ce1ca652b5	\\x00800003aebdcde2f94bf9ed68e20d23a64f3ebcf88801614e51ddfc2113260d7f1cb24e8064a3beeef24fef8b8bfbf60e1695d71b2c45c67912bff24013b57d075e9e595aa894ce465abd09796b9f072501b8ee139e103d3d201e08b55d4f2404de2a82c77347105158c91fadaf2e1c062c5d1fd7e617303fa461a3e7e84b7b0edca31b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1e5463466845a4a63da7ad54127762bc50328d027b8b43455557f9ce3359658cce7d8c9d86fc0e86f2ea4cf557f39b117604dd0fe67078299402f0b026e8050d	1608125177000000	1608729977000000	1671801977000000	1766409977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8048042bc01e2eb529b0457b0dd990a33e396bc2e7901f18e267efb921df3e815665384d710e2383d16a90cc9edfab80e56fb34e100d67a02ff361e2c3c406af	\\x00800003b8235a4232000afb4bc2df5869bd6fad78a3c1e15c5d0c4d4b55213bde843f12c2c657a85e6a430f5e125a6569e592f2ac397489d860d8d3cbba62c4328c3e39299443ada562e2bab99d42d04466056ae05d8d2ecaa416119334e2f2ea786ddae955dd6fd7c30ab0f5c50e2eed9e437ee162a99ea7fc94aa78cca6edcb167e13010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x57aea05e847a1793463bdbcd41171e02f0697c9ece814f7432f8f80d30e4814123e71f652317f764ad7a7e54e619a026283362c4e31ff62b650875f6a2e5b10a	1624446677000000	1625051477000000	1688123477000000	1782731477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8268936f9536cc2f2c326aaf483c1efe093ff631021235c20dbd681585f0ccae8eee26fe35f18e8cce90c3deea81f1cdc7c8897126e42f1d0c2fabbec91c8058	\\x00800003c5af3bb32b6b8e9a72acccba3b1feafb9e7145ace1df0c0d57317e33817c12b63ae0f34e120ee964394205eab9082e14f82ff95c342b3445533ec309236c44007f4939fe5a73913ea39e3ce2bd6134fc70f91b9a5d6a6d71fddde1b8d79bb75157c2468edc4d3436e62e8a8ace4808be8ac527703a5d9a4baa34253d239a1eaf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9c5e8d1aa0ebdcf46b7b88dbedfa5c604cf012a1f4381dc5b35028099f3ddafb00ff0462f9d66d0d6710b6e64bdc620bc42ab440176a8d58dad5d07b0c46e90b	1630491677000000	1631096477000000	1694168477000000	1788776477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x84f0619bd17dc02faad274bee78fb381f6911ef5071a94e6546a5704670855089b7d0a606061e299e7fea6f8552e1b8a149b6f398b0ef5c9913a851340b4feca	\\x00800003e587ec69ee46ec5ead59bf6fd85637f7fb0857cc9cc5d7afc8e03188540e16a5e09ee91d27561be0a8e2e696ea2b90bc80d26fdcbe216132c3139e4c593b26d36234e4bff5de4477115a910d4db7c897353529a8a2e19c766684ddd665d9d8b387defb4225a481429ff0ae5f94550f976ebba065f58c8cc25c32d0a9cd5494a5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x762d81cdf275a6987a35ff779edd299e44c440b35e78aa91fc053a60b21e5d429fb51ce41a659f8222b005e62284e8d2814effed30802d08a70e80eb9b6b680f	1634118677000000	1634723477000000	1697795477000000	1792403477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x89204fc3e2cb9dfbc62a4de42114a10263ba472c0bae80223a9af81e53edbb8c721c5c89548d711ad7e274e021c39a1b048933e047b6b58122491a033d47c0ae	\\x00800003e481393b92999a404dc2844c8c6c882e3c01372ac061eb9c64481ab5c17e8f9821c8027cf036bb9708a4f5691090cd40d5b139a7db6c8391e47019d961407d041eb35b0ae977c36c81063bc0bd8add1515bae3276522d14b3808f1eec32052182064286e9aa8f92d5fdb95d34c3eac5dfee90753b98ce7ddd1f0c388b348679d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2a00805876851f454a4be8650a95bfb53590b8d9b090552590c60df7dfac1079bf2249050d5dfc8bfc2fb317834fbed6a7b0e8120825a2cad7fe881b2135070e	1628073677000000	1628678477000000	1691750477000000	1786358477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8eb08b01dcb5fb9bb8a5a5f8e6985f3bdd05ef6a293938594fff54678a7a4dc2e2477a851429e219764621cf8d3664b632505f91ddb9c978a71a97ed71e8c350	\\x00800003c901e3c6d786aa021dcf82d203cb3385b1bb5799d20222fae57d428244679d1ffd064ecdc284a853b9212e73064b376cf4379a43af104763b88e2bc96a50d105fef6b9ca2cf859c00c1e4fbfaab40040d501d68860b4b8f84c59761d7e9fc32128eae3a8215b6d13c0a66e2141aee9a6ffacd848e63f64199518b8f24d62b173010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd68c3c4e01b514e11af7f51e62e8831fef1fb1de76c630aadad4f2019e6bc45273c57df277d3582544bb9a4862219b7ab0a72118480ea5c052f793105ac83201	1609938677000000	1610543477000000	1673615477000000	1768223477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8fa8b0868fd976a9b0682b0f79b9b969cf3c10957b3ed81fcd6b23ca9cd4755efeb2e5c84cfb3272dbf50cf7c2e41563f2b2da1ec2c100bc90fe96fbdbce289a	\\x00800003bf5172b8d630701c8eba42fa75e10ef16b2379523bc6e299115cf97a8c0742aa6318623055f1cdd6dc2daf3fcd16b0c9a0e7affa58d94ffa6fa22e3b2077fe3158571ba572245d7e6451a57bee66d1ab44ff241a119fa441ef9e5abfe858c917d338e5f76973480efd845d315e0b198c9c13ed23f428fd7c732df6bb82a037b3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x50d58fb05708f1d99dda0aa7df494f00062b3a2353a500f1e1db76d7ac38a0179cea742fd1f18a5c7c9a6cbaf9c5de2bfa955c3302ec952a02ae7e5ddd65ab0d	1625655677000000	1626260477000000	1689332477000000	1783940477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91700927537eee3d025c8517539c019cf48f363d00955a91b1112f5dc692eaa2b944454d5e493620bead61fedb02819b304ae542d5ebd304e206a32a243c145d	\\x00800003d89f31ed9a35dba27f2ed23fc9b4d9396ad140f97b0b3611f915ba7b6771141474e3042b3751b3e30dde11b07d74fd042856cb51dfa2c973e5afcde17748540611e09c3e6f88767624e6402fd9211625f14393838b27384175872f8422f5a80cd7d50377c7ea0a3ad290fe0600d6fa0df2d32b2a40e43103008a80c92eee16cf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x26b0451c1223ff5448202cc24e03a0c3cec0a779f9b32b38f81112608f4aea584c9c6739ed6355aa6076ce22eaefce5b41d8d540551b39c8dc9c69f8c3b16d04	1608125177000000	1608729977000000	1671801977000000	1766409977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x96f0841d9750451e72123d9a3fe1ce29ed9ff29e092794714da688845fd58972b8352d4c9cc8bd1c5036860fc075dd4efb60e6d7f5e3a3286c7ce61d259a2d4d	\\x00800003b7082090ecc5579a4c8d14095df1962ee0ac507fbc6e31a79013e4675c4c32159b813d8f66ea91f7ccec181c236d223afb89efc840d8d46e3be0462db60a42737dd12fee679b0ba989890eb36e93105b47a5547337e81edf77c87b63799050bb19c102f54b6dce4ad27d7c793a0b9320ae0f70e818865a21591993fa7377acf1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2d81aecfc9f8e0927c2be80e7966276f04cf24530f9e321e1a9777f9217f05e7e60ddaa1b2b7367601b29c8c9c20b70225a3f2b5edf2d58bcad38d7fb4dbaf04	1609938677000000	1610543477000000	1673615477000000	1768223477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a103429219de74870591e019566dcd536df95096e59c64e2b87d479c08654ad9d27447f3e4abc5842c8b03ac9a79e60eae642a772dd0ba509207d3a07d2f9c7	\\x0080000399bb0182958b1e7c33c301ee7f6a61a2bfe57afb89f11755960415ed07b2724b887938c8e74529c008159e175905f286d9266dd56eddd66f422557ca60d8253809e7edbe00154e48d29ecb9ccc5183f06fe2d74c21bc89f663306ff2ada248081e0e4859d82c12a4e3ce7f5cb2440542eaa6acd4cf6d9e6cc32edaa006b90d17010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x33cb2b0682ef5da730b27367a19885fc6b762ca9e50ee3764f47c46f3e934edb1f0e8e52b9dc23022693c22728c93933f1144fa9335914c99249f9a56b465d0d	1608729677000000	1609334477000000	1672406477000000	1767014477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9bd4213e0814584ae6a365ee181718282f4a9f1e8a948c36b77088e130d493fdc2f0df0416a09d1d04ae72e1e8751de8bf42eb5728d502814a066fe8a3189a5d	\\x00800003d072e7d258519aec83d7f32fd3ed3175cac8abc27ceaac4851bcebd7bd8cd28c9ec55f2f62433b245d480284f7f777b5963d709b20a7ea0988b1ca73ccd2d8e0ee6168dcf7873d7270adf6a6095bc12457f7b912dd65f6087f53e825e79c12be2013a92f23d886b7802acc1643112fc4ef42b95aaeaf971c6d7c7b20a3fa0189010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x85682d5261498c620961528655f75365ebe7fcad2c0906ae6c7f18cf3dc8112a26dccb803d37b73af7bb04fa153ce93053f8ef23203bdb7714f8704acbcef006	1638350177000000	1638954977000000	1702026977000000	1796634977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c1c5c79a314bb4c06b7be083cb1598e70295d49d4a780903f58a6a3f967ec08c273055771f2781b86e7fe250dfa430670954374e0d14e8af794fe2773169d71	\\x00800003b18912426d80a4ebf3225350a36814c6144c6cfd5fb42da630f88bf74e3918cbdbfdeb357464ea45a53e5b3bb0d4c30fd16f7fe82419accf14f06d58f0097a87ebbd82166b8cfee7d44639dddf4d4b5d9e78391e38580e5bfd8fcfeed80ae6a8c07351b141886481d6f27d128b2a7d7acc43146c6422e120196cee01364394c1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1c694a90bd09f307f20289c509212024216162176c61a687bd221bc558756dde7334975170afe73cd3e1265fe595b72fc4095524e83e0900190a1e4b7d2c1e0f	1637745677000000	1638350477000000	1701422477000000	1796030477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa12c84e7a86103627bcf1375017024f81d1e363fe64d8cc07c6b45fbbe47e53a53fe823972f9d3f1c42765bbb2a33d1d1c3f54bcf53f9f033e3a4fa0eb0c50ef	\\x00800003d45ca88a388a3ac786534dc831c1ecf64397efa8e30db9c08712bba5101d5b2aa545d9954626aa088e919483bcc7f11f64269c0c3f2c2a0d99ae842f1aa1fc86510ea735df3a89fd223117bc159e6bb780bd0064cf4b5a4d3c4cb75e5acc99b72b6d6709a2208c14d663a9c3637a431837d7a0e81e1b87896309dccecba41ef7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe0b0bc68c2a184b1c91c399c528b3fa4a57af549e2e2fd23dc31c26871f2f6b522ce1453e31d0d24edbd0e2de167626068476eef3d2211c69c55e6ec9ad9a103	1626864677000000	1627469477000000	1690541477000000	1785149477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa23c87b5d2366ac9a949801bcb2382b97f6f5b28f68480dd8fa96425c2b9af7d1e5a72b58e5febb5639fcaa0ff70574e6d79cd18d548673c41a1fbb844cc28df	\\x00800003a79f53118f4c316bf79942c27a00f056031f700ed963737df761be39ea79624676ca29a109cbc9177507d65933ff5682e1425c4b2a1ad29a46881df03bea3eec6d8ea6c34af708b33599e09089bc3c2825a9fafd5b7833f540c67463236ef2be735855ea3a07ebd76e270857cab47bfeeb530f69722ea053564345fee1480a5b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7c2af78db1097df214352fa0e156c568d7dc6f3f720da786cb93e138ffeda3cc2e553f4f34b8c08d81e9aa96fd65fc1a249e4f634141e7c53a5c4bbab5b12f06	1614170177000000	1614774977000000	1677846977000000	1772454977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa51003d514562a1b501283d8fa0f21283c4d5493ad4a783cd544e7d69718275d6086796598fdeee92394ad8fa4b0eb30a9782e8968463b95023c41991ea66df9	\\x00800003f4df7fea4f0c2bcbac431eaf84f4b4826c2ad5374f10c002207a875e29918d98edaf7cb104263dbb7de9e525d1d96ecdbf140cc2641efbf67322cb2417b08c8d3258d7689fa04aafab6096f86f5f4bcb354b0f64d2268e14a027d6a67146c766892838a183684c474e2272d58df0350a3b6b9c287a277e3dd22668d0c8d4f347010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x649c78d4a93255d05dc2d3834c6fe0bc3d6091b61fcc7204bd0909e0af54ae74a055a41ac2c6ece96f80245354c8924956e0c4a4eed31c53f54ed23cda00ad06	1622633177000000	1623237977000000	1686309977000000	1780917977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa89c08218dca9d68f8b512f8f65765a8b3f76a180ec531cb750e33953ea936d92ac85e83917c53156495aa71865a5db4392db92205489ae0349f110ff4863410	\\x00800003e0683b56453a68d2296a2eb4ebeaf3866a53136cd2a098ff57ff558167be992f0fba8f4e015bbd335ecf4f345a873d7e1739ea4c46c1bc123cd165eeeb48a8cc8ff7a6cc057d4623e28d1e36c2284420f3a2e06f3b584f0676b54f805e99ef59fa023c77addbcaea619d9dad8595d6d59be35ad6ab63d0cdab8597c347b34c35010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8d609162bd1d05193ea19690d97f0d64f04f50212b7bd51a5e442d3122412bb24a2634345bd4936346f9a0e86df4ee90d399f73f6acf20994d90afc2b0a62202	1636536677000000	1637141477000000	1700213477000000	1794821477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa948cece3a2e55602ed761679e7d33aa020a0695382e1510b5c49b3c18c80955ff41837365cfb67897aff02a2dfa035b4199546dee3a39ac65cbe2a787e16b8f	\\x00800003aca5393205df72e8d4280cf05e4ac225c526cab799d501c10cfd044f9445b05524c81b630b40a587cf43dfa10bad63b9a0fe70c529d752698d0781cbd44186935f3b907b4548ccaff7a5778587dbd9a7c6ef4468a37aedbd40ee6a90a5db7be9f8c9edd09c408c8b01dbc4d3a9b6fcee9931723cc58eabbb1e4d5eeb2d17cd2f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6f9c275cdf71a35a9ddfc27a9dc9f1c63a85809c609e806660ea008a2a6dc0ded0891c13de6cd2be902a5cf636f2e72c72813fb5674b18c934cc0bddfdb1a90b	1637141177000000	1637745977000000	1700817977000000	1795425977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9104bfefcf7de55c7f1d8d4fd5c6bd2b0ac3f6a3145d240dbf8cae6d7094105b2438e27220a2ed63d0d8ab46f27876f0c6dd0dbbbc1b35beec680b5ec9536db	\\x00800003cf05a2bdb8d42e412c0a12903bd21dbb325459bae20ade4e0fe0b373653bd3de3c49047022db773ac230fbacfc7c076789ce9de06b3cf07db6d642c8eb0258ef4a49f5811792b0e730d15f2bc36b80be798c4b6e637e75b05ba733fbb58cfe2cc4c8c2d0288ed3ef892afaaa4fffe760011cf257d08826dbffe7d4f7f35f679f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xdce4014c9998976663e11e33222194b3334171b261d1d756fcb46b9c46822945672ee8067a40448753df60241c9cf6505ac55b7667df221f768a18b9e3d4840d	1622028677000000	1622633477000000	1685705477000000	1780313477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaa1c49991339861c3ab3f8a160700ad24c6bd65990882925e5052a30b6ff52e51589f68134009d4e963169d34a05ca3d19d33ebcfbeaffd4e03f8216f75a2468	\\x00800003af67b18073731b2551af4200d6c7043d1c5d9bae5e1825b45306da2123755535b0885893e505784239a0aed488a31ea912c4a136fbcf0b304a070a7e914ae92ea3ad553408e51ad5e35103770d774c9493b0b9e62be605de3906326043d5a153ce454a22f75ff371529b984071959840d4b407b154b82e3d38c143f2cfa6005b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x234127165c31012bb909444126e97d12bc47056841f0da60958aa9c251d2662f427da20469404e5f04093bc9ecfbdde6f391fd4e4cee8675e933709804cd270f	1617192677000000	1617797477000000	1680869477000000	1775477477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xab1075a63eb133dfad4c6c36e62de11bea819d2f7f17388497d3fb917552c6e49e6f413a39ed91ba451f9b7ca88332afa2dfccbbc3bec2ba0b8757717676aedc	\\x00800003bf09e11dd91bed23b1b89773589c32dfb1b13cbf05866526999bb12a59585c71ddd81647a3a6690c23aaee2babce66c11dc376a72a183536db7038bcfa094aff8c289a7494bd3f5b0e22bbc3456b63f64e9b5e0e3aa2411a1a1d79b8429c0b9cc22e03daee0c5a70812abe76a93b94aa1b127456d451753a1cd0983899c1c2b1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf25a6c57e3dceebc5c1e2dc472308d78582295506400df66371924387248cb01641051d3f11020b0221c08f2532e45dd453a1f51e886aeaa95b28929e425600e	1626864677000000	1627469477000000	1690541477000000	1785149477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb1f4cbd95d2c1548f150c1a99e70f6e982e43430360e23f9dcfdaf0656ec4c7d13285df357be8e299a37f502e209389bb19bc32419cc2aa5f6a86d3a289b0ce9	\\x00800003bc936c18a0317ed000b7b42e8f9d0e4147bcaf5858bd5efb235b845adc2fd80b9e2b6789ef8bfce1bd49ca9dcd6b669dad04a5b8931f81f64adbf0a67d6e067935ff074161df3e3f7d3f3a4afc0b18f8e5681f388c8957cbfe321bef054cfac75cd1add008e3521e82bcbf635bc6e0733243d96300a5e13a50623ecd91f48b87010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa3e6b9ba13f3086d1b0ffe8a50c547787a7fa72eefe6aaa798c325b00143a9c5662ecbfaf8bea6ee0cfe9f9e731e0f1a312057584867a868d51b477652a44d08	1631700677000000	1632305477000000	1695377477000000	1789985477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb4f09809d49e0175cb93fc9db8d11b8d663ace22ca84c82b05a3f798124a274d7df8e6ad75435b12fdb16ea653bdcca92945e0f59125dd4a843864a916760897	\\x00800003a91479119abd644a15dbe486fb410782181a011663a1a0a6aeebec05b1a050b5df86dd56f2cab5e9da4e6d3c89c49674716d1b28925cff0320d300efd73aaa8fd1cf6a03fe6965be4f124b5f16c1b30280c6b216fe8eb7ff40db01b134611799da73f61b2966167880e7300d1ba74730919de35eb7194b4e8439c9f73742e83b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x364b034fb31c5649e9775479180a1ba20851015ad9f050a1a433cae4e6a42d0dbd0a57872fb26468f0279e48999ff65a34547fdc7555ec21a667ab493b2d8a08	1615379177000000	1615983977000000	1679055977000000	1773663977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6f4255697cf1e68c8ac591352d1557c8d2608d15b0fb7647b25648f647743f7ab259565d336e1fb987c452e2837285b31c854f62bda51f51f6e73a0762fec58	\\x00800003b9b11c115ef06140495df1fc296b8109619a087677fa50302fa651fdb738ba0ace25286286c4c1311e4ffac14142b510302d886986ea59098778ee51c3ffae67ee4d309e537c18f34a0b044ea1f1f0447f430fe6959d39bd49f648a96126107b1a5a94de84147b5670458afff0832271e0616f4181b693ade5356b67beb454b9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8db928881085406cdb51f5eb966d80cc63fdb2309128a08efb9f0303c1e27975bd7c08ce97e9773f3f89527637007be2fd475a599bf70752065db15e3a02b005	1628073677000000	1628678477000000	1691750477000000	1786358477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb930048fb2e05b85132eb7e7c851614b8ff1b7e432e7eafaa3d51df524add493cd9d96c3bb2e2daa38e2f0ae6376bcaaabf6bfe84b66964e9fb3eb95bc5c0d19	\\x00800003e3b0ad343631647c080af7c0ca5b08c0f06cf4c0cc9a36247df9e2b54a0e3cc94a3d94ba2f97033438842ce67ef1b0f7b4fbda238aa6b2e44961ba721025474f7964547069e8bdc0d9d6a8610104e2671532884dfbc8427ec717e979ae7bee4029d608fd287ff60008c82ba3351098f0afd63ca2e9ad68bddb8a5fe5c4aaf5e7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x39a01d8d12460997588d13414078f53d2fbd7344f63f76436e97d45303fa9127ea9d363677a5c8060888246c0a8f2521c7447aa9b7a4e5b5199f68c5574e6509	1625051177000000	1625655977000000	1688727977000000	1783335977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba88ec0e653fa7a1684f57dd59d76f530e680b235aab5734de81eef86053167aa00efc25bf74bf678d944320105d4be47acce171583fbb3e3b49e00038bfe0bb	\\x00800003d5a24184a95743ca5b0c6f4f8be21251613011dd65b80b70753f05b9dc22417be15501943cb2cdae0b414218fb8a7bf04bb4a1d6ae334f5e1554d8a241d90df18a143ab9c9a4191ef6cfdb2dfc54b7586cb66621906f825cdd993362d2b19ed8a6bee33ecbe350a7c3f3b13f6d5ddd9cf6f52c74be103588cf06558090116fd1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa46a94a77a66ae41dc7838f195556e340fe2e8c82f7be0b7627b2c17f30b35225797ad5f5e60b4a89320bb82c77651857e8c0d7a52faeff73e4e9a799492d404	1615983677000000	1616588477000000	1679660477000000	1774268477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb30fef5129c5e20d98c3f42227e7a6046d6cb3ec272b96ac235cbfcc14a995efc049e9a6f9011bbd7367056275448635bfc94ef0611649fae258c64f60e1a13	\\x00800003ba96d6b6d6236736d0b21e414cbb50039ab3466aded07f59e32a76d01971278f243921d515aa34da9b3ea81661471fa76511674bf68a45c316b2184bdae7d92a26cb1f11907bf61e3595ae31c7e2c6f474334ba1d375a9107ab05afa4389ef1d580311d53111588be36f86eeaaa9297465a2fb279d3e61c5face74e12baf2e11010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf10239e9d2a1546e74078ca303b37b28734aade86ba91fbc6ea67826a3b80c08e6265aed9f4509a3a81dd5a6027741874d01ad3ea053fef3325064bdf2572b05	1637141177000000	1637745977000000	1700817977000000	1795425977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc5c13610801c878c2fef779c1e8ee5660f47f601b4473a70aa6daca3fc552d8fdbf0825fa828094a03d0bc700fd72aa5200bb16e607dbb0ecc5ef536088aeaa	\\x00800003bbbd6dcdd82d31fb858dee8b64a581eb91f9390d3c2ceea6200c8ac41d0a33f25dce738926af1bbd3afd52a8b443fc05b90c0b7c7b9a9a7b048e3bb879576d073488a7074ed0e019476ac1c642411e1e505980d719f25487d6d3215d6fd9b65773866b5172e37ff72d904cca14850b314e7d1359361c860385a97c0f7f6f01b1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3cfb62b5e35daad888a612bb88ef12fba029334dc95bb90e5a4e8a5306f0b4f32caa3ccf8db580ef346b3b0646c47274c0de335382bea0af3e6c52afd6d3d008	1630491677000000	1631096477000000	1694168477000000	1788776477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbe7c6454f57780758260f908c2f66f4d4f7ceb7d4eab978e8115fadf94d5482d8e7ba4980c5038824c2c8d0da7eaa367bb17444f2142d003fcff7963af7f3679	\\x00800003bf0bd1629c429a644c4194f83649ccbb7223f319c423c65d1cbeb17167a198fc566a37c9eecf9d0a16c97081d55f500b566c13e3464db057bf5763ad84acc370e6b1e6dcef68739d88286bcf94343b9e2d94fa1d32aefb584bfecf5dd0ea6810aac446057c991b6443585755ecfc651256d0e6224d510dcb5b27f798ed538eed010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb98992fadec534eeec6e4ead6cdfa550f70bc8ae39d4cc3522d177704c097a081444cd7083a399061970b07cf203213e81d868eedb92924f9c6a29e2ac5ff70b	1623842177000000	1624446977000000	1687518977000000	1782126977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc24410515c2b00d10d585ba386d732621acdf37d9c19da7c88a4dab330e6792e3770265ed55ee9f83bcb3e1b238f3f2472aebdb5fda3af5bb2b200b09a200a0b	\\x00800003b5042512dedc3d116182aebc9a789e6e430f0a78f5f122e2caa3e44a7d7176b98860f150cda5d2047b845b32dccbd4a6e69bbc9d599265c816280d5296f15df621f1a11994fe68215ce7e69634d62fda55f71e0bd664c174fbfd80141f24014ac54b033b76518ae1542cc3db23cdcaf64d5eabc400308f6be54147df93a038f7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0e72fe5b7eaadc29ecd8dd7819d28a69ae13975ee0de64b511bb445f43f69df089527cbfcedfefafb04fc781e0d3de5b4582a4775bc14e018d1df3879237aa01	1639559177000000	1640163977000000	1703235977000000	1797843977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc4c8baec3838a98056f942be7fa94421a0d75a9fceec8cba8473a2ea5400c40f27f88f3959699d8d7063a642afa0bbd14ae4ad12b7ba9c9b998c4578bf0908be	\\x00800003b84c8754a1569c2705c85378cc4d8d98fba41fac46637d76c7cbf8cc0e87c95384adfef5e349efd39d196add6d4bcb438d1331d143c097534c11cbcdbc23db05224d55c8eb8f5f96d49c985c1c908cda9753b8b91ff9cd50742e018b84257975a0f973c1bdcdb3a400c0e066d728b565def4a78ad4a459cc18f61527d0d00513010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x552d48f963e9fae54cd024b4953048cb2b1d1fa748229ee64742402c8f1bedafcbb5ba9775f69d53079a3a35527a0a72e3f1a36dabfbb4ad6bc6d119b6b73404	1635327677000000	1635932477000000	1699004477000000	1793612477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc50067ab5b59fdabafe921b3a301c2d2aa4baadb07ec03a7cba9dbbf3150e734fcca685bbca879b5327ad48153020619df16da7bc89d51d5aeabff80acb7a9b7	\\x00800003be509b4bb2ddf910e4a5688f8f10b2ce8cad17067e1a3741475def5d25cf5c22e82186f26d3022967214857fba1970f2ca92d1f5648b8388cfc45f458941a02df6720b55943869d4994c9dd8b716b928de2a260b258238ca52b0e8c9e1fe88c2e6d26cfb70bf4625b1f328d7f028aaecab72768ad1013f22c97f680b6ea85609010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x600afdc0c5592429e07832ad08c7112e68c5813140cdaf20273b9492b7a47a0afad5f821a88a80259396bcafe6e5d58ab4e5f9b3990d45fa498a6c6169da980d	1617797177000000	1618401977000000	1681473977000000	1776081977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc5e4fce135d06176704244b569279a757478afa352c1db5ae1369997b5e1907ef54556c7054beb441fb337a676469a50a1380c78d46507b650dcc8ea897b76ed	\\x00800003cf274e10061d637fb740a9d1698d4cac7cd14a964617b277a384386214c9eea237df443d2079e20e7a3a84dca511d91002a4f70301d79d92db4bd7f074a874e2c4add228f7415222557cc50839523c486d30a4c422663ca57331486945685219c23641221f9c10b5baf5aecd8fdc3287de7a0646dd41fb4c243ae0025d4f26d9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbb20137d037252cf62ebfa6387f7980973e6084ca0f55043a8a49a4cdcc207bf5e35e810558c04f7141cde7339ab8ecb153e2706bd7dda60b06f7759f6f2aa0a	1613565677000000	1614170477000000	1677242477000000	1771850477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc6f456caf6fab44180d1e0938232c5a8adba37087adeb740593af4f0b68263c9dba9c56b915e2ee018587851d413758f57b9acd7dffbcf5151c6697cfbf99d91	\\x00800003c11bd01d00913fee0a9b00148009c2f27691083c0ebb1c7da1f9a4f39b0a54342449144ed4c0e81de07153c20a954421867f43d10b564b1fdaa8e50df44944ed7583d356da70adedf17d5102d56c421065cb5a2820f38ce82143a9b36aefd0b3d52a24190bf7db5a87cbe240394b35be572c1ab6309ffec32f8cb13ded0bdee3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x66c7c70fd844f2b1079b0e91764338b425c73faa238d035e64e194862c7c47f9e3928d4e5bbc2eff5be0d562ba0fcd7bc219aa0072b0e80594e63bc7638ecf07	1636536677000000	1637141477000000	1700213477000000	1794821477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc7b40b4539fa0777737c0bc5dd638c24f6151edde400269929f33880f673110c8579e362b5bd73b968475daedd05b8e30b3843e5cdcd18d8e65c832d9434cdc1	\\x00800003c48861708d463942530244aa138bc05f147e3293b31b3812947244aeaacab974a08f8ade612502e98c8f2e1c9e91d2fdf7233ca060c17eb931d10493864037b10c0327e8f03363eaa9b872bea1c53729fe3e7ac0be1646a52f9b5a6f8f21bd636fa4e7f52d75204f6fd0308d136030a16a15d890fefba3669370144d64ff285d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1e50c4c1c71242574add2ff3f10162643b70625cc530fb9036b9010dafcf053f7fbcf98be25b1978d85af9a77f5c1924f4014ca35312a50593415e574db7810c	1630491677000000	1631096477000000	1694168477000000	1788776477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc95c9de2f5a67434b5a21a0b18dede5f24ad517863d9c0e6260d33a02491fa8a37fd399a57d6652ac0ad35a135bacbe4e288cc56156c4f6ad08e401af2e5f7df	\\x00800003b7bf4f4a61ff52374a9e910d1afea5fe4280795ffd7b89163d0c0996a9875555711c8df8c1ff8b9af264607c37c74d5a86a6a90571e2d5f90b957276f72f4ec44c56d2fd257dda49636abd645badd11420b68ed38ac7d89f57ceed62a25e83bafe6429e3840f43aae8ccd99183e6358f230c85716dee3594e4b0726604a3cddb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbabcdf389da2ef79debc55515fa9862f75d4cf6a2e266bcd6edc4f658d17dcf225ff50bf06de4509653144f2de6257b5b334857884f101b170ab751bb3680605	1632305177000000	1632909977000000	1695981977000000	1790589977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xce5c34d673816d16c4c9e90952b42afd345dd5dc6bdac96a3fcdefafd46c4267ec4b044478bdc729f12fe6f97ec0ab71d175ba0231f837fbba8d88bb49cf0024	\\x00800003bf62434df6d846db10d2c3813becf08cd6234b87908bc248384d6dc29dea905dad5d3bd38b5f6a854d8a9e62f97b3372c4ccff2e7aef8921e62ff33c29fcdc24769a3ba36fcb6e2e78b3c906b7ed75064d4e6f59c3edf149e964d95eedb44eaabe4b979e0e084c9f53ddfd4990de3aa0e65541759eba2366f8463d60690cfeb5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1b829487cfb0ffdfc27162ab655ccac9646c7985683be0b284ce13a05da13af67cf357fdf32fb43869af3df8a5e05ba197ed8b222716607dc2fb2e87fc636d0a	1637745677000000	1638350477000000	1701422477000000	1796030477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xce04aa6e6e4f2f5f761e6f306491df6cea8e825acce2566873bd0cc40d5cb9da8c7835fa777cd3bbdd3087ae389ede42eba525f3e0c86e684b628ef1c4512c46	\\x00800003b0f1445ef0d18c49275ffe44e10fbadf4ea2fbc1850c45a68f31815e928cf3de0f5980af8f7086a619db8f5fcf5cd8157164c84b91a6f45e394cb27d2cc04d04bbfb6b5fffb9cecfef52b4e7b6f4b75032d683f8c5e8881ff7a9cb0b290e0106df27bc94c7a99ea5b2ade9d5dba8576e7e074e1639b333205f1a4da7a7233a05010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x11255e5bd322a2ee78374dbcf94a48d5ca59738e4c4b2d7ed0b4256724b8aa9862f9b2d843c29195ffefde4b1b1b07a0da4ac849fac7d46ab840706c05d03f0f	1635932177000000	1636536977000000	1699608977000000	1794216977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd5e8895dc660a05cde0625a240abc76d4c84a8e4516d1de967ea5e35303f10bf4217fc5b96743a815476b7ea319ef66d9dbd9440d55a474f8e2d0d7184182dbe	\\x00800003c16cf234552615f68fa22b5d0624d7058f66fca744aed11058a2242ef14264cb4bd7d188a4e8c3abc1ba89da3d9920b50c4fbc5447dd2de749a6c9a302320a010019ce22827a92de2cc356d7d5ba7743a67026649caee37ce562b3e4db5d1976ef47d32210170632b0655c1a354920461a7489c9536d3af8501b3da693193a47010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf00f3a1ce89f7998e08ee1ae9f4df88916add7e1151e0b2d2f8c4b8f21d5944c1fea63bdb5bc2062c7c2a1ac2d7b4a6a6cea9269725abbaabd1a625a9c6b170d	1632305177000000	1632909977000000	1695981977000000	1790589977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd6f0545e2dc227dfc37a86bc5e9a68fbd8a5e7fed2daf93c6a30d9bbacf33b5bbf8dd8148e7b874c2de0df769d774d4f7131b53cb81eb5e1c109adb5b91f45fa	\\x00800003c1d264eadef798a680cea6177a90d9325eaf20dd5fc39d8685fbaca2d8d7b77004d4b77c1e034c11031bc4ddb73bc0ea7188bce64e6727ebf14765f269d187366a80617fee4458cf57af930777be98a073c2bed662dcdf493e7dfb8b300c3ec36c14b0cfc42a19e7e640c8fb40a97d664cea72fb6eb2845e7d946fa08fb5e33b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe3c660784c0ee444f6090807a9c4e28abb48050ff3b9c2d2b46a94ed2829f09d04bab8025089452a7ae850baf15aae63c09b509bc112b6ddd7ca66dc98165002	1609334177000000	1609938977000000	1673010977000000	1767618977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd620cd5a709c457bece7b5189b703764f3a24d74283ae1e8b6d2cf278d5b33f88b6195ea1c45a7d64a3609680bea2e209b0051f7a2e50be01da5422912fb7fd0	\\x00800003a70387b1a7d512bd75cbc2c085bbe098b2197bf31fce1bc50cbd24c70013bafec2567fe016761404e9dd18db566c4fb3685cb39ebf9c023ea97009605682d99391ec346ca876839aba0ae9120713a1ce55a5dcd651db3a2e2e5c37d67be5c17b328416e5188007e26b06acf432a44419bc663b1b45ac63da1d7640fc0e1ed111010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x89002e43e3d09cad27d8618ad0fd501db7cbcdca81950f3c107dd856ff81b4e948519d9b2662001ec94677fa809b7c7a43a64f7e21dec42d904ccb6a76d4690e	1634118677000000	1634723477000000	1697795477000000	1792403477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdb1c197de3bdcfa24f9097c6bba1fd4b3bfef5164a187c347b2fc66b9a62163351543aefdc27f860b35f5af43825f4747d9147de8e288824348e6d82377d6d76	\\x00800003c2747e8e27a35407ea4f990ca5ca75a9a8f13958ebe06e656e84f96f704aa4977e969e2acc326ef7c6f43a0fa9578dd20e5c3e2c9e50d3a11d1a9e7d1a8b87a9e3a7ab8b789216ed868d9cdcde1a0547fb9a020f03e394e4e442f595d936d191fc589ce5ac72f9830984e603a85b9af69ba56c8e3dfa5585ecfa65d992f9c811010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xee723e6a26371f461180bf9310ca6ea978a334d65b3728f8738f077ca04e35fd649f8a8464198ab9f4b73e8aaef39a5a17c9c829fbae4a6f0d5e467d8d63da08	1622028677000000	1622633477000000	1685705477000000	1780313477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdda8e52630740d6799030e59a7e14ed2674c8a0040bc4863237dc17802217c394d743f7d50c89e44995ef9312743e16d2a7b1fab3d6359ad3da82a711cee4e52	\\x00800003e0bb7deb4699ce485f552c58cfbed91da16b286756f0bc26991741357b061e0c79c6ad56803a6f46fd762a03265b9860ca4572247bb2eef59018f6618fec85d5ca65ca569d66abe75c9faee69c27308ca6e966f5f5be3ddabc17fb3a0b02c13d1c249940f199c3887adeb30a78ba50c9bfb12189bf1033ee4485bed481b0e639010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7367f593b1d7631b2bd566ef1518ae5a42984f8f33144e5d90b92b9b353ce43c1452404be0ff7f541e66cfe79ea1c7d64f0e2967a7c94cfeebe4b76a80dac401	1615983677000000	1616588477000000	1679660477000000	1774268477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf7c80833c5f1bb188e073dd85081812ef6f9be8192e4e33bfca7d9de1274c54c3ab5fcfc03531ccc4bc94f96f478fb254d6cd4d8e83209cc6a5789e37b63264	\\x00800003c6522bfb27a5e20225b053fd77fac5305234e78bc4e7b7e3f756972a4bee3662e63b468e3787b1bc902c331ad8ecb2f285cfc02bca6de8a22ba8aebeed1e7c9510e9f11b74c3ff022b5ee9cc36e4b4daf034dea1fed432b2598b77128369e9b129870598fb2a6d6d8c1600413bec38aaf99566e2dbb4b3797cc3afc534e28ab5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf05b40178c365da3d153f9b59e0299e07f4c786af941eb2641ff2acb511f056b6d9aabafd2cd14721c230a23c98851029d592469f5dc021455e26d6fd672e20b	1625051177000000	1625655977000000	1688727977000000	1783335977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdfe811e940096d484c4eccba6c53b65b4fda433d0f757f3c42696aa0f88e252aa11ed007046d9ab1caed55cf889ef6969a6832756b1ef42d671fd2bb87c46a1a	\\x00800003cdefae58e70f6be5414497b7bb5c18f1f4639f48644c1dc9e28baff57c7e910273e95875e369efc2b91e73979e4691d2258f37ff62bb0d748a07c16b46fd0e2e2ec5b4210c291cf5f7d7c79797a137f70899e551db5077c319d1a5d1d99f137bc078fd7d49a356c6b3ab9795fd5364c836c8b405c00a563cba823e2f39ce7b15010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfb925568cc1a530336ab0df3fd8a6cf48102b448631cb0a0b866a1387f6830adba8c104032d0f48fa40a76fe043189bfe3ae4d5b9aa652aa897cfeb7f0266106	1625655677000000	1626260477000000	1689332477000000	1783940477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe0e01ee791e5e103142ce29ff5488c8a4541226e78a4dbfc1a592f1e91c6fda1cd7eef3cabe106701cb0e664ac3ebbc86089c1ffc8864526f9db1f18cbe80c52	\\x008000039f3c162633860faf343b236382ffdbc5f6aad1d378e09df473acfb7a492f417de0a82b3de4696b4398d00a7a3dc3aaa088ecd76ee618b4e326413ae7a1f8c81bbd49b42f61234abb564d1e88b1fde55527c0ec7d94647310a7f196bdf5960a5324615d0946b7d6592373135f3dc36ec531c6dccca17dc41f556b4538a472c32d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6c532faec2d88ff2b7c91fb81ad6197a75e2a1b342f4a8c5c4059eed5807036163eb4adf4d44f63b1c58c46b9718a7a50d774e3bd3ed9a491d5cc79162df0004	1629282677000000	1629887477000000	1692959477000000	1787567477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe09cda09129ef51632903a442eb5aa765233dffe2173b9fff3db0dac1826ca542d41daa4a23c37a73b77e147edd5a2baca9308a67231cd567f8d6b68e99aec4c	\\x00800003a8782f99a5eb4f6cac28bd7a833b07e0217bbc1f16fddd32bc990933af53d2b37db7a2ad1f14ce09201eead860c019bf71bb4722f2de94486dfa378ef98f87f5aaab3fdc34c3b9f467ef4a4c79c6070a950c1795594c62d0c8b94fd8e1ff8c7b691b85281be76694ffa35df28eea21adf39a9890dfdbe919285141c28889987f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9e4f590568615aaebc05fbb29febd97fc0caf64fadd399e5b9dc4b31863ee0e63decb67f28c2d32cdbac3076badf4b83758f12f2e359c64cca5c9beffb89a205	1621424177000000	1622028977000000	1685100977000000	1779708977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe13cd6cab797bb07d83144559dbabe13189eb04b0b6246ccae8a8d5f1f24bcdf6433e8dde63d13fef02fa3c6bdd5f748b115698d2e71100d2ab80869c1b27482	\\x00800003b73934ad3ce58874ceb8bd834e5948f6c54753ada67ceb98ee2e3a02dd11579abaff623097ae7bdbc6b8585d29069d73d690dedc8f721264686555ddb8e75664fefb26677ee525c5f4686115b8eabf5c57f41848a26e60ff40693ad086a6ff0fd57c07f6d921ae4c7373410bbbf6aa5662841b8b89ffa48deaec1d63e6293805010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xef5150458c51f6e50c5adf9ccc5e30c5202b24385e45774ad8f8128cfcec143b73df7851d01a5bdf00992674ada17a24cab8f7c206743f4763518ae94daa390f	1623842177000000	1624446977000000	1687518977000000	1782126977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe29c91ab3bc122a7768e34ca5eaae68de720a8915183be66efbabfd4fbd208bddc6bd4bd1ba5b61353003baac892cca518491ffc7c729eea6065a009df611cc2	\\x00800003a2aa267dc9d924ad6602ec7dff6cb8b7a2591b465e13154330a46cec5b83e42687cc3c5b8f203358781cf60968d167d9f14394472a4ef46dfc9269d6a3e7731780cecdfc19ca3ed21a2742126d47dcdca9301e5939a470fa38ddef6db24eeee5277560316ac0d727e9211deee62639352520981b8f761409cb9015954d308ff7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x916c9b5ce0acfdf35c94b7800f9f72d4cda2bad01788b539ace94282cc951a1ea42e1ab5e5c5e01c7d97ccd3672c8326b2bda7079807da0f3127fe04cd5fc50d	1610543177000000	1611147977000000	1674219977000000	1768827977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe6b050b48cdbaf1bfed9535eabe6bfe9aea57b8eaf19b4c3a3c895f24f74735ac778f06034c36b7329738934cdac6bb00df50cd3bb8e0eae561c465a84f52da1	\\x00800003becbf1711ffe804eec13d9955f53d4b9030854bfd2990f142bb0116370460b6de36c7ccb1f53fa2a334584a4298714b5a1ce1d6634a3581393b1bca6f13f38c6089ec9a3d28c295137893611bcebb918a8af54077203fc2ab8be35c9cbae0659245263f29290e4125a8ee25af34d74dd211423794ec6794c44ac4149d03060cb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc0e63d0a86d72a5470e5ad71e880b08ddf8662e5dfcada54f2a229949c55c3aafec8c6df211f3f2b434fb030074d60864e1fc2f3c024c25fac749833ba6ed504	1623237677000000	1623842477000000	1686914477000000	1781522477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe66c9f3c56af441508e33700b034b7a2391d9f6652d12175f025438c50ee7891be617b3893e069c367a32fd004e5d3924364e64ef3b08f6affaed4bd6e99fde1	\\x00800003dd27ceb24bd1ee7712286f366f67e15b6422ed1835a6b0fe311b26ac84a4939aaea8ca6b37f603aa03af2180c98a59030ebad602034db2ec6531f62225d306a7659a77b8da8a3905ccbd6631e2a916bab12d86a6441312bf9d14b83106312898358c92e1416dc2645b61b4c5ffecbbe97649ae83d71672786295a8bdae642b1f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe0074ecd2e1fd0eaa9ab760154171821206d5cf80fdba1849ff5dbed42090d7b4729fd01448fc9e600bae3faca87b5f91fe6600855faa9623f6ed2cd73cf330b	1609938677000000	1610543477000000	1673615477000000	1768223477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xea04c292d4fdf396382ba113e8d1b12ea76aad97770540573237a459c79ec93f7a7af6d7d839763fdba6732ff556cee332a64648d5f973ff0135b056ed6c2a5c	\\x00800003bccda7104a4ca93d577b7a98840197dd4707030ea704bfe13d741f2896a0d93f2421a8636f35d5e62f0e49ce4a89f8247a740be6e7a3b2f1f5e196a3d072caee95cd7b3de5156c2227ab47c8497b2b2128765b4b174cfc2db676918b7b03ee554b5f9dc03d508a25b76129206f34ec6e2b3ecb72faa91ace1ceaab70febd9a3f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3a7906023a7decc44e7142729525d940d6e5b3d828c547f7ab6a264300f329a1f4dc73df4c551bf756d1843b093c95b62d3b2a14630d369dfbc0a6e253d0710a	1619610677000000	1620215477000000	1683287477000000	1777895477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xee845729902d20063f979df43c69fbb50d66cc04371ae438bedc8618de9520fd82420673a9fa9c98a67f54661c0b70b819a190121abfe8fbb1121f2aa3c93b4b	\\x008000039aed40f8f9fe4a77e8ee95b23a0bb1731aa698abfc90e94b57c94fcc2f7c81eb3195671f1048e74f8877b12ba9e125a78d93a8db69f1a4564af047c5dcb935467d98999511248b5b78a43fb073b3439d162e13ccdba75a643adea8081484b3d61a35288c7f30464d0b0e1d0cdd0ffc01a6fa332f37de6af58c523e7107e1e3ed010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9f3bb8bf5df0d9d0701029faf68ed7afe8e82b94c59bfc1c32ac4c0e79b11d9e3f884699a7ce3ab34dbed23fc399c251863c715d06e71fa676daa7b0e6d1f405	1609938677000000	1610543477000000	1673615477000000	1768223477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xef7cc0296633dbd6de328d6e7f23b01d4e297ec200933a85c920aad4ead05eae4ffec47f561cf5dd1afe8a8b622c86b4dffe1f75290245e9c659a73f8c424543	\\x00800003ea6a160fc8f247a9b2e1718a593de0a97fdabc73749efb5139dc56a7ceb72dc1fd607001569d5d31baaf09dad67b6514ab24e28b89ad6bc58f50ef727abfc6f23db408aa21d2a8ae2ddd120ab4af94ed30fa36bfab8d9cb98b96d800978c9d728c7bccfeab46e50bdd4d6807b0f1de4bc641d578a9e38c651d966547ebaf09df010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2b87f0d1025d7704cc47e186af60ce697faa63413b9074978d88074efe59d7c7ae3cbecdb5b183ae753b1579973e17b0d707a694d4007c3e453141d705614102	1632305177000000	1632909977000000	1695981977000000	1790589977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xef08fdbe7f4bcbd36ef87c749d97bc7bdde89ef20a5a535f8259612ae67386da5aabf163f27084b751d0018dc9abe75ab07645aeb22c68a608611c6e69153b26	\\x00800003ee7c7f2d2765f9286712aa370e5bacd972b81e3957d56b505a126d5c69cb2f29ee05d5b3c1a27689d156502bdc6b7a5d33a41ffeb415d682c396a5e603bfc7d4c920ad74b176495ea635b7a4f9dfd338cd6c87774179c28dae9d0c78a32a6bd3b2517e30415495252d90df4d750ab464172ce898ec9cc392f25af0fa5e27632b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5dde60dfef8e74f5047e101d4552d143e8ba1671a76fc1f40df7a85434c6edb9d53e162dcc3feccccf786a8569453318819f07a2a4caf6ed0d99aef02e167f0f	1633514177000000	1634118977000000	1697190977000000	1791798977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf0347912bf2260df8aa94be940ca0fe95fc90075e7710ac85801a10c4b12c1f44955d8925394de74a3701ca4251d81d8cff35d0ed21aa98c886fba201e482a42	\\x00800003cc90b5e7fa2fa441926694e60c3a7794834ea1002d6437f44388e3692ce67e461408f6cdfe02eefdc765f981ae39d0d559cc69c0e7af3425b82009ddca57a31ac49c5f1354ba57a17ff301e700f83eeb6fc64f8d760c05d6c8c6a37556972fc13d98f4b5803a8e26d48b3d90a5924656a7a23a06af7e4297da76888e1815e975010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5bc2a79817d23867c52244baf781c2f830ce0a4e1432359509d5778298b161c7fdaa681e6c3ee47040d212a590bd67cdaeeeed69bd8f0c11e90998c88d407c0c	1635327677000000	1635932477000000	1699004477000000	1793612477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf03c2f8d8b47190a9b067af39a41817ce478fb8328687e653273ec0f5f0b33d89f3711a5f83862cb8bc9c37c1c454a9a191ae051e7065217dc045e38d24ad4de	\\x008000039c2d615f0ad60f1260a98cef3c62fc324e9d23efbcd194e5dbbfe9ea69453e9db3983761a59afbe8ab98d2b4741a84bdc5cfe92f96a506e5f0927808eca02c898f60a6612deedde35adb811525c55c45ad2cd706f07c3806ce43a2a3d7c55cad0556fb5cb0879e01628ac1847d399fed497eb2a7d162a7e59978f8b3f054755d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x45b7736f2f4fea643b16091d99abd9038c482bae3a5c5529c8f39236e6d5259c96417fac4f5c74bb793c87731cc015269c6b092e153995734e36034ca388100a	1615379177000000	1615983977000000	1679055977000000	1773663977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf5544b0734bdf08ba351b7518a4e18ea0530055fa17fbc40662a5000d4ae247ace9f6797ca6ed25d46a666818cdada62e4b47749b0b5170f388e7d3247ba9ccc	\\x00800003c42d6a26be2d55e3b2e8bfb693699c41f542cd4880e4ac1e7e090597bd628fb6ac8d605256bf772add2d1eb5dc573d0833f11542e502557988cf1d20f06a055ab0ff7488e294306213913c5c21ebf2cc960a2cd83533a1d7f77e440b8d880c7ecb2d6a24d8416dd32d7422ffe8587cbe9e2afc58a0a995e4270162e7051941f1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x892321dee431f9049d01b97ce1724dea64844e480340e327e650e830ded7917642eadc488f848dc455d55afb5be936c574bd698d8103838865becbf21d3f400b	1619610677000000	1620215477000000	1683287477000000	1777895477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9f8b1027b19a4f5071102045f258aa40e051d2555c2d3d6377bd0489949684ec4c864641a7cd080b678ca3fa88145b84a6a4a73a3017adee4609af96df205cc	\\x00800003e0a4904a4a5b40f0ac27a7487faa58dfd2f4764df6597280a3eaca494276ed05eea28702b5e1f10e4af415f24a8cc70249ef506b9d1a089eaa6cd2b153828ad30290785fcf28282185e2896d21e16632a1f9f316e6e78b6b6926c70b6daa2a83889ff67ff83e05a0c3cae39074ef30cf1483b6d0ea6ae7f865895cbc0524359b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x56800364f0089f7ca6d2123e95d9e0c2042756e203ecaf5aa5da8c344f860d922a73474117f01ad99b7e7b2d347425f324b2d4b7f2bfe7b468a28fac9896a504	1632909677000000	1633514477000000	1696586477000000	1791194477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb141e83cb9b3783ff97c891806bad5fee1ce1501a096ce9e8346e23dfc70794c7681647535e2eae6974b1822f3bc182819740143c878fe9d9a6e6f557c12b2b	\\x00800003d4ebfea96cf9fc0ec6bb0dedf2e3cbd464b33b0c59bf47befe11657d6abba2852170de2f256a4e59794a32a6b76af2041a57a90d618fe4953a1e6890d051ff6e3d93e1616bff69443980adab2e174ba5521dc8f221b30840f700d1281a1657e4ca75489ce9e8ba7f84356fef03065f6e7d0829f2280c935fb4829d4824bc3c7b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x73f4e7c02e02aec4b8b8b09cf1e47003e7a852e79b4f7a8be393319757dd8d5cfaacf3143fb87be4260c57000c69ebb08265401c7836819fa3761d7e994bfb0e	1636536677000000	1637141477000000	1700213477000000	1794821477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfd58e8d34bff1061d183846faaec9998bf015f7ab1eb3f1a65a27026b7c13a9689cbb89f5d7ff2176ec3f3c274a90ba607740036a3302f138ea2f665db289c02	\\x00800003d44184a2c8a47f1193756e30d48219ea49fe608b5bcf8a74c8fbabf2a978ee7b0f242c27d61bc864122930ee78a9eb2438f49126c40b3c607d899379f0f8436430c21155cf7f5af7216493d3d6db608ce1a9c86b9918e4baa8e32132fe385a9bd94b4930dfecb5c548a4e03cf0027aa6cb0e40b3b79d285619b1190f8feffa29010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0ea7e9fca77d9bd2455ac10e3074a825d1633d26c85d0c0b81a23c26b8959a54471d3adea0c1db50094e4c7d029e80d42f17568b34396c771ea8f3976f80fb08	1610543177000000	1611147977000000	1674219977000000	1768827977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfdb43762e04bd4b3cc98e648a5e818f40877186d745d48e746f4ac50a406ac91d2ce3530685a9335cfbce6286bee1dfd91567e1b86608d0fb16924be0a631d67	\\x00800003b2ae1ef51db3201213658f813c17a92fd88c96a9d8859e5149f01fa6b30f17593ea7cc51a8d8f91f281b663d0e633f7303e28e69fd3b08e7d069486fd0f988024db0028d0dbeb722a16ca8e31c327952b959256275acad937b75d02856fe72c1e378c0d6ab490d42f0ff9b97e5f16ab9896389ad059e7d6dceaca4d0dbf5529b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5e76a05b6a64cea4bf9bc4fc088f70805670de1702c3c182ce0300462aff85f56cbb7d1f4695b746ee747a707974e79bbc544e04c43398197ab2891e0303d702	1627469177000000	1628073977000000	1691145977000000	1785753977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xff7c9fb6c7380796603769a4054e788e23a52950245ebb6025be484d52fe1dc480da926bf5ebb11b4860622d02c2320402293ed467c3397c12a45ddf3aedbbdc	\\x00800003dc502996c6f921259d8ee12c92424d5f12647be4de50e8e2ef65a20a5afddf884a7ebf27f19d95f76ad72bde6006f91d06abd1168380a7ff3d4cb386fd0f33dfb91259d56788330c314d938d727f2ef7e925356c5af0244c0de5ef92e9b8c04d26542974d3321dac029a0f826c4bd2bf77062f41955c996fc567cd64252ce2fd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2d30fc98438ec804fb7985d174ef654f761ba24fea563ba0adb973e78a813f27c13554250fffd1e8c49a92c3b9fcff74d915c1fe76cced9244cafa270b9e660a	1638350177000000	1638954977000000	1702026977000000	1796634977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x006987101cef20902d642d94a5e637a05b11abe6eca02100814c4cb5757eef72af9dacba3e2d7145e682fa5c66f96cafee7113aa610eb6481bdcfa489688890b	\\x00800003e1beade7b9bdc502b06bc72451b98e16c3b9cafc6c3b2add53d951a8593998cb4e40bdbf96ba24cee3ffd546c634c65e154e589085a985ebcf7d996c36b5435e9b1c8c6c91b148ed7a9e2b6d107f18d623ed6a054c6fd832f549e6cb9c49a21867d28811c19f600ef3e2126719f9510ebd8a88eb59430115d3fdc7e5e92f0a0f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x403c2d0326e7161acf43751c8307335270fb8d2e0ee9efb8ca1e98a49195249c661fcdc1238a7a5a40cb701835e08ec4cc23a2825adbe587d2415a395a41a408	1610543177000000	1611147977000000	1674219977000000	1768827977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x02f5d3e00ef16c1e48bf959056710e036054b3edb78241615b9eea09e5d5e548d9923600621b400c1e799eb2a17b12052ce693ac6ed3f3db6105704d24d418ef	\\x00800003b35ef5dd9b8788b23f44aa4eff77723e00ecf83faab6fd68fea0b2464ad2150ce891c6933e835c0433770bf1eb9fb0a6a6b61755a6619901f9176b174ea19e170f1e1181655e5535fae74abac016827257b74a16b9934d519584481d981e6a8d20398f5a62bb14ca00b622adb7d5cbb82ba1896fed3362d508ff843c0f4cb1ad010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd85b1bae70fc961a72fb5392a10f39b88455c1a659d7d61d215e9c714b93d6bd11017b81e3fbde00580eb091e043971a3b809cca91dd4446e1ed1fcabbb45500	1614170177000000	1614774977000000	1677846977000000	1772454977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x034d224ae8750dc394c079bd8f653197bfa06b949951300e15a0e55d845f49f902d8accbbb0d6f4ab6594e4132beadf3975ec993b9c9adb216f0c66c807460aa	\\x00800003bcd55fda9369cc73070dad3288032650169a09e5016084329a76f0fea4db419d3e2d68d5d97ba789dad336ccf5abad0e8cb6f8f26cfa901a2bf84dc98a4348af02f2bb8fe88a653143692fcc64e78dad6a25077d87a0658a63de2115335ca18aecea4042106e9b3c32b0a87419273fe1f00a673c5a0af8549e971770eaf650eb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x64a95482d4f0fdf5f2a7d09f6e1151fcb5f6035f4e85f20c9523bf03599c88b9e46aad236f4115e701def64c29fddb33782bbc7d498cba6b62334ce264bd3e04	1617192677000000	1617797477000000	1680869477000000	1775477477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x03cdfe074a4e2f8082c48ec7f4d8fbbdc65dff5d34326d167e287dca5f9cbadff87f0053c6f31b99a3bcb3f4eab4498b14a624eec0ba2c12b73d9397e20c2b41	\\x0080000396007dac7433635d21aeafe209c00e7759bb6099ae201982ac44b979d07e5e524937ae6a77ed9a8ea470d6854fc5cea580f9bcaaa4c687729fb2ab0784177b6889f037b953d2ec44435fbbf4918fdf50ebaf9cab1e4d882ffb1cfea902d7b4cde824ca1d1bae07c22b0ae812c2c28190c858439e78324a2831982f9040a73cef010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe2c500ea3fa4d11fbb077deb7e60f1a0704712358416591136b8deb9a555b12de95d592a18b214db0a87e4a204f2be7e021af15d9cd6e76ac0089bda6d43c204	1629282677000000	1629887477000000	1692959477000000	1787567477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x058dbf47bf8a48905f583d4b8d28b03ddd9447d311f600f7db70d853c4e2d4e621a864256e6a16c1b5d3b0f3c00fea3afbc4b9ae8027e0a5c2db79a0183bcaff	\\x00800003d2129129be34ebaeb4d3a1ce1d6f637fb4515ccb41403a6583bd16a2e838a3015464d3d37154d54e9f3640c9d6dfc1a534fb9d374d0a990ba3d888282ef442243c217a49840408e34a307fd8c1b6627ce268bb487a9256aa7de518158ea6d0eb9344fa31b07d0840740babe021ae5e14817feaab15972e42264019effb41e5a3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x32e6747da77697543f3430eaf7e8d76f86ec61ceee716717a88f29bbfbbf12be12caa1c39680b7b0939c247f017bbad234fe5e6a6a2d0eb4fbfcb443c40dfc02	1631096177000000	1631700977000000	1694772977000000	1789380977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x055d44e78839e8f8ac1c15242491495a34338f056a8ed9dbcf87513cf33a2f06a644816eeec117aa434824ef59413bff3ffa6d75f6b66f6d33462eaa5b729b12	\\x00800003cdae936cae0732b1e88e6745a79db80be57563e1af6f6e787b85a107f0cd355f946c0ed2c701ba7c57bd4b9056b2f771630488cba3b620bde7d89e9c36293c04d359edf97a0197d842580b8b76f1caa8aa85a944b72f7b38bacb0b86116020c55300ab05c0262d00253323eaadc55d066a095c10f467a11ca5f350375927e69d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x92a30ebd433f228a788cd9b3de13a32da04f895af2d2ccff347ee469d7bd484cb161ebf55d49270f33d8e409f19916f4abbd983a10303f40e1b2dd62cc9ad00e	1628678177000000	1629282977000000	1692354977000000	1786962977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06416707210c55e6588255e89720c4fa03e112e794fb5a65a069477a57591affdbdfa8ac429d14e0f8c630e0785562fda0d97c0c2077c7509ba35c00d3cf718d	\\x00800003d58ab0ae2dad3f73882a25eba26574d32ce1c6280d4e48a4885236c008f1c8df92e81027f3e47686b4daf8a03b6abc2e282a1b8f8585cde128def1fa97c1167fa5af0760f434d5de4d968d12fc7567732fe36879680b095fe2f1ca964278a34a2b62ad17b5baf743bd5edae87c17579acdd91fae560ae8df465da8d7c8e0ecd1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2d25c486ffdab2a28b5bfb1dcc078911b742d0141bfac919f13e001d4e3b06cd238612a6885e00a9842af89d9edc4df09ab01789aa2e70dee2ee0d83ec4dde04	1613565677000000	1614170477000000	1677242477000000	1771850477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0899221bee962d96e94600611415aa483b823d5b0ec1643c9ba498f99f38e95d30a5bdf707102605d3a155ca3dad2492824050b8cf7536c9eeecc5b9a69c5f28	\\x00800003cabc30e8b6d7fecb86656b48acb87a13d9884bf0c737b3b97ace229081ea43316ac2725a802924e7fddfa65ebe6dbe77915462137fc6805c3c61d657a93044f018cb749f3de2e0c17e7c1305616a2762842cb14f7b48612a6626476eaaf788238726c951d35942dc8532a28128bac68debf862473b98a6fc679938bb4388ce05010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf3ccd39d320f88aa5f2ecd6f87256ecf3d11ad6d67b185f6b1e0992546e2cbde89859f3e162daa4748e8e9f6dd3530ac36f799fbdf7b1b1424b4fd8643adab09	1608125177000000	1608729977000000	1671801977000000	1766409977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c51b09f008e308af85d801ce1ca31289ba9fc2ea0cb1adae976d624145369f84b9ab5494f8718b1b4d269e4e8a89f396e26f5e1c36636c55fb932c018f8304f	\\x00800003be457d143e1fa2a7a641674bc5b28865208fcdbb6d35e305dc47ad05a4416edf4556ab4ecd339972c418c707274cfb266c824580a2a1f072ab05711b83c120ed3dda3bf14e4ca9285e2cd1c61ee888e738b630f290f1b63891918e47ce70bda619d78db30e7a37bbd4386bcab38bfc5f03580e225a870ff32053d0049dd69dbb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2b7a2286d2b30a1b613ec3750ddb0a5c94abf829da6895d9f6ffb46c6b6cc8723414ef5d4fa4c92183eba5646ac758f3acca5e1b33e3173e9e293bd26cba470c	1636536677000000	1637141477000000	1700213477000000	1794821477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x151dea60ec9e6f48f56100cca1c2b6136dd479809f9c4055964e0aa36d8ca529e30955776efa3f250fd0f290e9fefbec0eb2e0d42f286aa80c1c67b29e65b4f9	\\x00800003d4fa8db13dd7867984be8d015ced2b48b1bda305eda4c5e412d42add1fb172928835626ecbdd23b77682d4f8d48ebecb341113b39ba4d5dec5ab15e479a60fdaef19bfe0cab4d7c853b4b15083589ff16a9ace575cb786fcbb58a97445b13f828fb3815eed8f481adbf8fc46d4e5525248e7e4c48617fdaa742bfa21b3570785010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xffa3280c857f22623286076782f1dcc197f917cfa32eca0fa533290bef9495aa66b3d99d0993ee639fd5ee779e7aa5382f1ca05c562b8b163a0de523b2b67509	1623237677000000	1623842477000000	1686914477000000	1781522477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1745c552b6ad136caaebcc479f0af0297a5aa2df06f9995cdc8021331575d0859bcdc42c69bface628a74d1bbda915ea26316d742e34433ec55b4b86d62088a5	\\x00800003bfd49679d44485b0f00830c0695f19404dce18f23272d1319ddd8d72a32b08803225cc3a77a0fe51af979c1d8f5c3dabccc5b83c359930efbe787bfd7a36e2ee18aaee88a69d0be533f3f70928ed60214b204a9ebbe63816d180cbd18a1ba283453d647019333860e484e1c1eaba498ad179ae05eee13d7da59ebe59f92517b1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa53aa30c5c1b3107f637658fbe0b08ac255ac764a61b209bca29e4cf247e72eccad25170d58602739728c1f8e5c7065bb5a0db711595c7b2338be9380b445004	1635932177000000	1636536977000000	1699608977000000	1794216977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18eddfb4b4328e1e985a92fc7c84e1e29aba70db519d145f2ba918d21a24cd62e68ceaad4c51f9e05121c398ed8869499fb343c374380d45b93da4f7082dbc03	\\x00800003d1f9dfd5364c48e5c9f9e3754ac90e38114c6f86babd934873d2323ccf720be186298b4cad08510933f8a2f14a57150f31b50879994f3b8ca78688404cda30eae34d5017065c4329706399ab0e11a8c7438dced0232723b73b7545865bb6bbab040f11788424df402e78cd5c8e3e775a7d8eda6eef7c02d15d74cc9d32391fdf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x68dae9c06295dee83544732fab7ad954c5243c3a9ffdfec965a19d4a60f1ce3b99db4e91498f3f1f461b1658cf2869440aa4fb3ecf25837063fe48c0673a9f06	1625655677000000	1626260477000000	1689332477000000	1783940477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1a01e70b0a41cbf8200f92f4e3cf100007678c85bc177569005e7ba3a166a785782a6f700c08de2d65bc2fea2ffe5ee34bf23543f27d478e1ff0224a59bf13f8	\\x00800003b972589da47c7cf79976199ab782b43015e3e087ec377fe67cc85d0f7984f986505995e91e2a0ad74b4cbf98c09ca66a43006e6fa650012373f108c736a178eb9db6c192e6cc0388d0aec2004c52d464e8270dd88102ef94a52e769d54f5bc6d54382d87bb5fa7e02804469fb530210ac240f25387ef0d6abff26785cae64b85010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb5a043adbbba59f7e21366f3a13170ae8b6f47bc2892b068de3ce7b99253f6ee8834ee2478a2438e704349cf890d2587bab75ee0563c9e2209a7d92be6bf3705	1611752177000000	1612356977000000	1675428977000000	1770036977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1bf5a7507b4ebc6c2dcda58ebde8e096ddf8c0b9513ed7fff5baaefa0f38411fff07e6c0c3a10963ec88cf24cfb62fb6a87916558b77216bf4f79f33e61d0c40	\\x00800003aa41322828b769764640dea22115296ac403d0069be2d939a8155f201c7faa4692d8cf308fbd469a9c56f8f0eebb924dae096890cf944f1e0348a36d62d87326cd19a65e2c298cea4de5d98eae8bd5139faedf91d6e9fdbfbcd21ce74330c8aa738c1d6d3644c80c317633850938df0e09aae1def743831b6d2504ed4f3b44df010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x85469f13d8dbc73568541757d5f748f8e71fefae557534eb6ba69feb4ac82427feecacc1c7d41e5c238c5d2b6bfccd65740488bb2ecc92092faad5e5be912b0a	1613565677000000	1614170477000000	1677242477000000	1771850477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e591da2e7813e71f8a11f08880e7a677266f69bcdc73673d1823232550025734f74ef3de493de8eb8897ccc3fba0a3a5a74439908c17037794dd49e7692e196	\\x00800003cbca68c3f10845be730f66b2f6913c767ba0d65e109fbdf815c51faf4a862db048318ea2b8992b9d98334834a3e248f7770ceb91af3afd33611e47a68b22988721b3a2681d4732ce45d960fa29df6d81e539add77bce623bab290832ee9c40f162315226362b6654a08ef9a607af14b1ab75b20a2fff44c7753b3c2e0858f08b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7b16ee9331d740f59e5fc53b0809132e535bc8374d04858322ea8474d0b973bfb4320d7d5e0926007120720875b9e89d22122994da4a67c6931774019696920b	1621424177000000	1622028977000000	1685100977000000	1779708977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1f0905e2f7221f2dbe2c46f6288cac2f3c3a5fe51f0d81a1b8a423e1b68df9d80527d571c83b2d2fb30e153586740fc6b0cd18fca364bc7e045c02a5dbc1536c	\\x00800003af95d7515051de265a15aa0e70391b086e665b028ce34c906d867901d265abd6d261b0f51708ffcfd64e16d963d6a13aaf8594c74d0f1fe7d8897cbef21a700d806f88decf942fbde1cbdcc869eca09cedb1ce3649ce48f34ba57a11557ebfd053a359a3c27331eceaa9cf0a6153d1491664033ced3003094b99f9ec90dc3515010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3cfe75ca170683c662974f28941f44c4b1a0d4704aeb43e1176fd476681987c4137ee7218fee8d32d5d92775285e8aa56aefdb813350315e3eb564467039ee08	1633514177000000	1634118977000000	1697190977000000	1791798977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x24c18f5238c795c3b287e762106122eba2139ecba127f89a63fe77940425046fb970b1d3f71b845bbbb0b2907be1f066c178224d98c111770efdb1add391b5ab	\\x00800003b2caa738b778cb36ac93b03e7519dd34b36a2d55a42e055ea67e3f7dc14b65be085080340545f753f681295dd7eaf6c8eba0d00b33bcfdd25daab8a9d5b501b069074a713ceee02e55e4f2ae0d4528496f9d8907bfd5b67ae502ea642f777e49e4165fa1298b91912e28a92c3f08ff361d5767cf396d074625d91cc2c9ef74f5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7cd52694bffef762e62d38e260268955fb9d8ea931821ed6a852be93eb4954437c16338b9657102a47e0eaf5ecfdc24165b17bd750fd19bad7534c2308586e05	1617192677000000	1617797477000000	1680869477000000	1775477477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x26e112c03cb3f05e9941d80063800757b25413b1aa56c6ad0e9cd149ef648a3fc3cfdc891b5dfe143375f617a043c8bc8ac49cf0eb69530c84c43e7a0d24b64e	\\x00800003d611b977930730f59de3cd0aaa502bc16edbf266281784149758d350d991bbd9f6771988a790ff371e404d664bf4b8df252210e1ce5919ffc3854f6e56de3576baaf9e85eb655fb90699db2f75a57eccab600145d71e80a00e6f676a691a2ae94aba5eb311cad407a412653059e2b4332b6a3e54748153b7dd1a7d35eb43bc5f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb3565fb418af199b8ad04cd2e99dd06bfc9506a09a7951c3b0371e44e330aff943c5270010d1b5cf008f9a8c71aace97acbf635d2840187f921d5a5b19864a01	1620215177000000	1620819977000000	1683891977000000	1778499977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x271975f21e7f1263e59fd4b49996eec31befe19ff4c627dc03364a86621ddcf71149be1aba5b402226636df6a6fb7e9511028c97555e2cdaaff63a7f9c63025c	\\x00800003ac64821943cd4b343e513549c25771c5759a300bd55df13f3154c2c1b39fb27851e3d54782ab8977c3cf7b64b040f7834716dfd0772f4086812f7b21e35ebe3186590082c9d3249fa74fe122c7cec12c5a3157b30231cc703ea2574c0c970bc415f32fdb0c32fc01dedccfaed11ddcd895e9efbbee801e224bcebb43658b8a53010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x87c6367b8987b5ada68fb1c6a8ec31f927937e0ea68107967b8054de220e60fa449583e61041a093f39087b9942db0a578a246729135ad3f745eca4303c40209	1637745677000000	1638350477000000	1701422477000000	1796030477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x275958492406b0357544c420b4d170f603a14c5d3022fe85a8632b37ff3abc901f8e132673dfb53ea879fd9b3a5f73c975826089ecc2591ae17a76a24f3225ca	\\x00800003d4947e3ae45de5fe113fbb7fb9b30764a31c358a0f969e5694ab8b04a6798cd4ffedf13b098e88e9de1631e34a2d9ab7f08ac2675967a8bc2c0049839b3b4d6249f508aec7d0ca700377a7f60a6b95f9061c167db77de7f565d33fda260ebb5fcc4aa5bb142bd5596a32de41657f9ab4f9cf2ec7eb3c97d7bb0744efc40d2705010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x59264877a863ee0c4ceec0a2f84ef9db3ea347ccda0eb231c23580e55eaf96d7ed21137d8304620f1d9bc8c52e1bbae5624124e4e0e92e20db811b16d59e3707	1629282677000000	1629887477000000	1692959477000000	1787567477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x285d9807ac7150afd8ee94cd88962b4416ef4ded3883ecc8da38652c20847ab8d76c836d3f78ebd2ff225559fee1b71a7af6a9a419ec3fc49a650cd0aba0511c	\\x00800003b1d1fff514d8c56d0b5591bc00017a2c60cef6f0d500d8911b522aecdfdd70da1a87193e4f1850bd2ae1f8dd47d1cb9d8509566f35474203fdedbc7e796844fbc9af5ab419bac1b12d7b6d662cbcc4b126a7ad86a5b5fa50a5f89bd1f3c01bb76520ecf682f2d257e72ae6c840463553c13f448b04bee3c0f831e38451b86ad1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5a094713190c0c1e81873909a9008bf3117c2ad9be43e1c5ecbd113bd9f9c48459fc13d464cde2fb72a8d30ec3f4b2733aa1ba702c88a73d07fc46da4ca47e0a	1638954677000000	1639559477000000	1702631477000000	1797239477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2be95348038ac12af37d0055fcd30c27ca381f446166602a2c9a600f8e1b1e1416b8d91cfeeb7649a863d80a76e788a2f74049099ae851086f64afade52ec212	\\x0080000396b8beec90d194021f9d6a67afaa4810e54f404ab45849b09fef6179c64654f1ee35f7c0570b346df248c72e88e07389291e7fe0c2d77d2f16f3ddf2a1803319ad32c50bcfa4b07ac6e002ab938305e377b505220783db304110f4e07fb9c09b06386ccfe2c0719b3f5be5961cca538a8b9fbb7f96307bbbae29e8cb6312b6b9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x49a4d71c9164e3a5f9d1986e02c35433144e984e6af83807bdd022752d4774dd6cb7792d99dbb20298f48753b4b99f98c147801069d1358bddebefa63d2bdb0a	1627469177000000	1628073977000000	1691145977000000	1785753977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c210332a214772da4dd5bb3011fda558204d6495d59b8a694bd6d0a0895d92417fce59cfb2006b80a1c8e2455e1c4dcf4b83e5ceb719d5cab45db3025a3b80a	\\x00800003e313b0ea902bb805683852512a8c6d0d21c9ebc7b1821feb495c355daa44d79656df36550aa55b2ced5ed6fbc795e5f36b974759420f410e64a8fe22eeea9d3ba2221ab1c78d853f4baac9187115a28c77ebb9f43e66f0a83f1761691b62c0a36fea91a91bea183c0c718548404ea9f1bebd8f26e9b10e0279f1efda3835ffc1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd4a4215ec6fabf467c9f7a0c00b17487efca51c2f676485d0b586e2c4320bf5a20a4e9017aa68cca1e27c2a86cc0ada9201f2d5e03b706dbfce975e3ebd84001	1612961177000000	1613565977000000	1676637977000000	1771245977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2e059d7d4a3f23ed9cf3d18908ed16f45aff598aed3693b0a0a33b009c5a4767142667ad7bae985380454d2541b6f0fdc7be2f0b3c17fc055dad39a7ffc2e44d	\\x00800003a3723f39597a0bec614c8bf747195e12fcac1e1873c29364e76747e17f05270b9c89a53836246d951ad980ae0df31caacb1d1f76376b032cf2cc5dc06271b856fd43739263d76857121700a49b3f1b62ef33617bc6a3237741109f18c959a65ac50e655492d6b53204dfa31036bbdd2590479c817fd34caf5a5bd41d314d0adf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe2775752d5f9e16e1c46e5b2e93394c9e7f60d199fda9515c18678593a661df4f4234e476ab55cd83276059786ca25ed830753e80452bd0292bd01770ac3520b	1617797177000000	1618401977000000	1681473977000000	1776081977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x31e1ab8981b712d8e0609da2ae2bdd964a488e8112921acc4775d8ff6b27f6c633631526f90e376a545e8edc103cc20d648b780dd175e501348bc5a7f9150e3d	\\x00800003a81613a5618d81ae48abd84941a2625a58a84f303f58a801a697aa86c84447bb919dd863d2628259813039c2547aab42645289110aba3ac89867112ea9533d65e66644500cfed2671660dadfe62f5a4f1c793b97927f8866654a7541672bffcc9057b5f347c086526a5cb8994f416ef2bf0eac0fa96ce0d54c8d6fe13be50b85010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0f268bf3b254caf5ab34fb4d0634ccff739126a9e3266f769ac02fc48287bcbc9001586b91c7218085cc075301a8be3fbe99f14614c8f4fa632e39e6aa991a03	1633514177000000	1634118977000000	1697190977000000	1791798977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3c7db9f1d3ce968948662f26c440bd1143d21cd4c78840908b22e3787caeefd38153969ee53801cb8261273747bc5b5ab6c9a85d9a19cb0a4e469013c2be552a	\\x00800003e0af4a9abb84bcfd7ae830595122707cfa4bab497fcd5b40f3f30032c7e60af65f214770a883ea663544aaed60410c755229c770627ecebd545e355a551b0e12ede0b8199ae1a6c1ecee41b8dbcab3524d0b827edd04fea2f087bc49d3665db883139d8e8f269239ed91be242c225846bda5666a5ed23d5d4ef29fe1ff8c012d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x97dcba9acd84b80f58f76649dd87fe7d8b786adad52078cf39c5c96a2f0a5ce6aa21033a6838ae669f39cb4c78f95511bfcbdcd230a630cbbd93e2219c64550e	1614170177000000	1614774977000000	1677846977000000	1772454977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4361f8ee97a9d8ee6c5e28faa763d8e58646f3b4eea1f4f9253f3469f2a401144d119a80fd5f64004e64a6516bd1bb1de1cc2b5e30fa062a807656b4a6ec5c24	\\x00800003c1713969cf3445c5683ce91e0a96c52551281a1a1bb99d30f8317e5d14d7d7daabd25c305462c77516d2370070f602725d256b839cb0c4dd8db2f4f02fa111924fc267d1280615e1701654465427755a3102978eccbbc4d254755ec496ed5a77a4168ed369a205b8ea795410d9aecd573653869e17c8b8a70b860b2f75a01a2f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x06c27d0ebfaf7d83b3ef2bb8d43a739fc179bc1cc6779aa8f482061394088a175b5eee4bf517e611590850341669b685e875910ed5fcd1df33d13302f2291a07	1621424177000000	1622028977000000	1685100977000000	1779708977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x447d247350ce6caebf4a548646176775b240ee5942175366f3d3af871e6238fd96f07c74a45592a9a02660f4c3a831b736c91e58a5fc490d5d9dfdfe480ecf36	\\x00800003a816a62db489b6711c2c24dad7c89b1d69f161d9357f8da745dfa45ad029f306076144991d7387b85cb94d1011b96085884914837d14aee561b7cdb86f75da7fa976c0ae54c027ef4ad180f507d4249ede9c9ae0db3727e5841ef6eea51e2081ea87174814c7f26eb33799184b820f7686228c4cb0ca9ba7cfba22bf16f8d153010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0dcbf03f20de5f7e9cd7dd545034e7c8916476f416e978f18ac731df84a8dd1d9f8684e9ffeed2838b31b89ff9fbcaeda7668fb8595b3798d3dc1a5548c36807	1638954677000000	1639559477000000	1702631477000000	1797239477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4609a06ad64d9f5375ffede303d6086d6a740e886eb0f257ae3b4e1882da52e43edb78ebc9b7f3836d91346db808252b8f383cb7815fc9d2cecb07baed5463d9	\\x00800003aac04b29044766094d4174b00e87cec5afe73980307e25884622d27021ec76fd07e03e89f118dc841bd5e35833d724914d5aa3dd185eb8a37c838973dee6962725888bedd121654ceee951dfe041c187e92ae1b7cc69c3d0062c2bdabcb0e7b9f0ac307add55a94e3ffea8976398e76cb02726b3c3da8acded478599bff6ae61010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6ac64ed1e92ccc24852294d3e8b8931a935d827ae3664b7e19587dec9975329029e7c968daadcacad47ac365793f5aad1f93f5c78216984c5dbc85fb6bd0490f	1625655677000000	1626260477000000	1689332477000000	1783940477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4879db8474ef5c1a761d5aeea6ed2dd707b96f21e60dfab94dc1e198a6e5c620534667d259219dcf64138d79444c569845f9447908089c01a1d3a8fdb4514133	\\x00800003c9d38095997d57e6e43c048e334a7ef80b65fcb9fcf383dbaf7f4be1af86fc395db182a3a1f5eee030f5b3019a1c2a1d8f9a1844c9a09ed9b9f78f24d1cb2e3f5178225f8681db97a05d95e2c95a4c2beddfc73a96cf5ead084e7e51175658cd651e1cdf20eb138d9ae60a19d801fe27df935cedb1763164bdeca2df3edcbf4b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3955fb59506e8efc9005d01c547748936a37d057d8b5aed64a5a20583ddd0ab17c092a3b310be5ec85f62db53883d6dd979d4a825ad77bd2893b3528c9d6c004	1628073677000000	1628678477000000	1691750477000000	1786358477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4bad630e7d3f33d02eef0bd99eb493fa0324d57afe5b63625055faad08c7b26befd37484f9a20b195655f12103565451f6c1b1886948ff588ba615123077f8d3	\\x00800003b758145a59bfa2817dd55c32ad33f1b7f232cb293d2a53b091e0ada971ea2630f52f3a9fc54237b32af8fe893605e123f77f974cd9ed1312d315595ccf56417cfa4365465a8c8a435dd370375f09c5ddbf9d1f471816798c8c8b4a1ba728151ce5d9b6d9d953d7af26fc5c0291ee2f26036b2f8df7fe91b3271f1bd19e7ca121010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc6826792e8582d799096f3175f84641a80bb4a56fb61ef05de504a101f87ad95faffc3d145132d04302e5fa3a5f109735eb1eeaeb72ba6d9e1d23842467cec0d	1624446677000000	1625051477000000	1688123477000000	1782731477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4c5192e473baceaf947891da61fcb74fdd33c695378df6d242d5f0e2946af9ebfc5f31c4e7ba97d88676c85207760fe040589c6e6129108fdcbda4b81e9eb9c0	\\x00800003a6f0edb9ddf3401efc36f74df0cdf5a52e4b2a26f756838189b11c18a83ac5d31e8e1441ecb377a980f83896d818d040426d9b0dd224142754ceb9ca96cbb2643df3fae53a2a4690aa8c2b132f9ca8fe41df48c28b71505982d8939d8777311f81c7a2eed37a9dfb4cb15e9bf8faafbeb81a0cbe0821356e7bfe20fa590a8b33010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1b05a7d8046a55e6b2287c8b50d385a4cc9696f96e7cc327683488e9c506dfb31a18df37798250e7c571b2eb33e5bdf62fc31d361fa5758933e7ad5ce995b20b	1622633177000000	1623237977000000	1686309977000000	1780917977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4cf9e1038b3aa0c402d74989cbde4b2b41b3056caafc81ddaf0a4732be5c4e3676d20752b0d4687dfcd5d47774202659cd1d1d1d0fbcfcbba1d9422845432196	\\x00800003a53475f070e13d65bc4b715abd84780ee4edbb7397983077cf7e516ed48ffa63f95c0ed597e4367387bda8857dadfdc3163aff9b700380f210703aecdfbf8ac61e30a1de08f0611f9d2818e1c93d59ef9326b411c1da12ef2489606bcba9a7d3d186c25b9bbad7b794d247d0c2819cdc090e872ff46814749dc97e393e2acc99010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe8472106c00954349011f56ad08f0cf3508c52aac950ae85849f80963d62215c42bbf45d98244cebc022771dd6c850daea5aa4ba31ab09efb060cc2fedecf900	1623842177000000	1624446977000000	1687518977000000	1782126977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d1537669f4fc847a4d22d564132c2035084a8cf035d3e85ab52eefa88345b05bc8efd805899f0ae6ec3f1032d9db8d00cf5eb8bac1d9ddc11c2a74b4b937ad2	\\x00800003da101e58a66985c6df7161801746b47dbc99d3eabbfa90c1faac977a25c715c108fc41fd5d47891f34d0bc774686db8f76f6b10194f6d407489ea5dbd1cd00ce8a21061254d9c067686bd422046194a1f0dfaad3a7cc716a68ec4656d2f7d30a71bb91fb11b909f7ae34ee601bfaa5f1d7d17fc34a8ed85f1b863aed427f35e5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x428ffe39b31473b5641da157cbf3bac317c23bdfd36ed1e86ba753bd34330ec508ea76ee3ade800b821f49f242a0ae9bb7fc0683e8e6f240f172703d75c8470a	1623237677000000	1623842477000000	1686914477000000	1781522477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5071555c55e1dc501b5db191a86e4474caef7f9d5540f07ed18bb495ec70bca4e09517ac5f928f69a78dffa9d40a9a9509ee0753cd16223d50a4e7348756bc32	\\x00800003c977c3b8772383674fa6fb26478c040f464e4425399fa79f29f1f9e0cc8a6932a169581acfa457cbe5d17addabc4a8b24c7b2a736e970a9998271486b07775324c03646770bde721c39b7953b8183ed65e36759393aa140f73a969eab820a353ecd04ba0de449c613f6f5baa61de6cb89eae4ed5f35171d7c840ab677140ce0b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2985bc874295d9efc45e46d1a9e13ba10c24c6c98c676e1175d8517e390d32035daaf46f3d1f08f0eed70ff58030cc2db71e6956b3cc347cba3a1fb5832be90b	1625655677000000	1626260477000000	1689332477000000	1783940477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x51b59d575806ddd4e37ba99e46f241566cfd3081f3ef8194bfc4f0dcf8a1bfbe6412fa4fadc3c576d88991ea1d5ca72a765552960264a58c9168ca4624a32899	\\x00800003e5f39fa258061644ff90d859a22894aacd8fcbf4f653515922f64ec73f1e59e8f58646c10d2b6639f01c6a3a3e60765ec477f7630df98a1ca7c6caeaf3ac9162bf639c5e55565301ee540538523c2a13f7d168d91774e22c98b050511aa6794b217cd107f4386122138c9d9e14c3790ef766a79798aeeaad96074033b5075abd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3fe212b111fa73e7d9666f996b1e9d713272990e2408ea28cd41edf3774ee3520e24b742666cc4a1eb54481a8a21ad1d80e39f25eb5fae0251451c5dc7bf490f	1632305177000000	1632909977000000	1695981977000000	1790589977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x53ed92ed8f264556a9f4c24de64acd327205feb9843c6237a2567f58256221df39fb56ab8c779d879dd8c0a1ef721e7451931f88c2c2ecd9c3043ee4b377e536	\\x00800003a5f3ecaf2220c93841aa208527d05ea209147f9c9048791e97899b5e5879b5892692a5599b22f9a1dadabb8de4b7edf15c25d6f48de614f9d7d70ed4c16d3a239b8bd525c4bab7f3aa1143a254b01555659f5caf4089e100ddb6af73efdf4773d510979acc9481c673ef1fbac98ee4252f5baf2c2eadf4aa36df23cffc7c6d35010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x995d9b28b2a8287712317f62331001c644ee36c4b237e5228b48085446a04a42544b4589e5429348be552023b1acf26dd074ff0f1ae54c87071edf515b908e01	1612356677000000	1612961477000000	1676033477000000	1770641477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5af1d4be8657bb946776661bbe8244d009f9a6c9bb3d31a72f257c32c19f8b0b6478f224d9e096c7151125c3cd53131d7bef7f340391a8bc3970520e7e15798c	\\x00800003c9c13fec629486c29f1ae6e84860292a7918bf4d607b8f5f00199f2de20da1500c8445f397f818e4c7d79b1caac027260ef7f8b2aedc7f02ac19dd2be98a782270799a294407a75d7838ba718557e14c9243c0522c33c58d5102c3080cbe911b66d2637793009d2ae03b17493f49464f32bf42ebe0e4363b78c9b732a478d643010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x071aeb7021be68be56c9dae7c74dadfcda93a04e33b0bb61daccaca190a1280c4513b6721471546bf02e9e22a6375ae1b5dcf77313debf045eeef71d0c321a00	1626260177000000	1626864977000000	1689936977000000	1784544977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c4d48a217d5764b72e1a6ea14a6b9dc35d2bf052fb937e022d0c993939465c54324d0542f02631889e9be18971e452041d0aae913d0cec4c1534372fb322c9b	\\x00800003969adaafdaae4833d77bb45443279e262f4792e5c4a1507f16613f0e3c5a06957c14754afe0aac42d48ec117049dd126008fe6a2eefaa9efd8b8a333836b9e071bd3be8bd3354f61a6f72c792b7d74462175995ff690e27e29e71d020b9b8ad7b2702dc854cfc38204e52d8f077eeb306e4d4778dfb8bb2f03296a3f32641f2f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xeb9bc1133828f337d5981ee0f279094404ec297b4582ad24fb8b125d0a0ed68046b8dda040283fb4e873374ba6b4db7f5e3d9391a37a419367a00dea610a8203	1637745677000000	1638350477000000	1701422477000000	1796030477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x60e537dda7877ad4f097fbe4305ab2cbcddc026093a8fca4b04ab6a90b333045d40a4ab59b21136a86f89e0096b2986dae7e10150a4dbaf493f8d5f8db099578	\\x00800003b9af5aa381284b25e9397dcb9616185e7b58f129f9ab42b0aa99fddbe980e43952827735d98d08fab482e24d1bf12117a8351319aefdd02ac9525180542eddb6d4db18a84cbe8a8113c71b8cbc3d243c153712dedfd5ea943e1cabba0842027dd8a8a3ba09ea51afe7eb84aea51cd7f81a7cad6dcf7b72272b33e7bbecbee0a7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x81332ce3c1aae00cec81db552bffae35f05aed33b70cd30e130736b01a70e7bbf6783cabfaca04a9f6f4ea1f6fcf0d2806b90d9fdbfce3034477ba7663c35900	1622028677000000	1622633477000000	1685705477000000	1780313477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x63116be7fb344f0973846995cb6333cfee5bcc6bcfacaed49daeb1c7225f4567f99a81acf4947942f79d547c7a87f67c550ead7c77b6b9c284afc95f0ff33d0e	\\x00800003be236a1519b9c4f46c4caf1872fe9c9c9c203e6e16bcc60398e5da8da2e52425caa3752681bd2b450f3805d0ba4a5b25944647c4cf49e5805db302b3aa16284dae96a25c0a8e3f5deba115bc19bc7e9876da248871ac6d18a91aaf1aa372698d1d1e0acdf2d55868c3dc362e35aa6748138ccaef679b2cfa72eba142a5fca2d9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6ed1473624044ddeb6155a3291448fd5ace3bc2a79b0855f802c108801a1e5ee93b0812f5aa009d87d8f1b1bbcb81b95076708b025e6b805f80248494f569d05	1611752177000000	1612356977000000	1675428977000000	1770036977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6561ca6ae382e7d218a9e83f066c61b42b2e212f07549e91ab2b671353d6e28faa17eef2d4509f1a2131b79a2222eb84dcbd6c6e5c2db9026ea2d57ff9904669	\\x00800003ba677a4ba7d367dcd3574496afa817889af0e8562ca5be4a190ce2f39e80bc2cdb51b411c6140effefbddef7d7f427dde0fb63b091028c4d2c61279a21761d2fc887a15b7cacdb7f6a9520ed79e561df12652e9fbcc54f4797afc02515a36fb1d9f69a8631023054703a391dcdfd89b22df70ff5d74cbdaa1c181cf35ed8976b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5c6c584bc6ace3db89fae947883ab649edb2b611f311c7204739d48d1c0e8c40bace148285c5383b3d5c8c696f2e3eef85824cdf3230b54af56e81fa79dc7b05	1631700677000000	1632305477000000	1695377477000000	1789985477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x69655fa130a486a85b758923ce53d0ad59bc0a4f3b7fa81284dd9644692315aa21f07a3e4f392687e7b04ca0c58d407eb2f169914ae3f24745a2bd25872199d0	\\x00800003b72b3f97c09f43bcb05f81febf1d350dcb636fa73323b60d78f747537ab33e5789641cefcf3f487739820bef1891006d6a416657c42c9a859840bb1c8c07d0a53269be2354dd92a5b43c4a394f21d8723a2c76172388359699a51ed6a1abd07bf509d235e5f157a7c902c8d49ecbd7a4bde1383359a599bc4d23ed11ca2f95cd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd25d54bd2611afbcd5af2c9f8a5bc07a6cb786c1032fddcccf29764eb7af38972aa8fc3b9214310e853eadc9b9fc8c6b7e114da6fa02a0ff58c97b75a9dcc507	1614774677000000	1615379477000000	1678451477000000	1773059477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6c0588897a28fe43fc07b1d662469ead15f5b843b7d0d629b6cb8eb1fa2e2265592f5c736ce4434332a35583424fd85d08a32cb1a14b2de36acce36dd957223c	\\x00800003dacb61b5d4c7580e3cde5ca186716d32af2f141e0a5c1420e75f24795842cd7b327be0b1c7f67a2e1c687d8a96c102ef0886748bbb68b2ab8222a38d7d2c072b844592ee52c01d10037c93f0d765d6fd31e60e8d2abf001951e5cf9767c6d466ba88550c516422a119e5529fc643b6850958fc698b871ce2a211a6b47db59a1f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x67e6c428704e352189fcfb62da455802189c88e48faf244cb176fd12b0bd8517f25469740f90cdbe3720895dbc8f8ff0b98de5bb522f925319e46025adb98503	1635327677000000	1635932477000000	1699004477000000	1793612477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70e11a3682674a43e2cb78076c888e03f375e489895713cee6027c1f31246d59b690b9f6c1dbced6c177251588bded7a44e23a6fb792fc3ac9c934e0928a2ff8	\\x00800003dbd8043216a64cc69816e0daa5a0df6c41d22a91886a5a28e4fff439af90022c933226eed12a8a03e3d65f61732488395cbc39cb43be782d9e2dece7bc9aaa55a93f3d25e05273c1474b0b6b799e65cb610bb59c7aa4ba457d9599ef3373c0e364cf96545545bc267f6b68abb159b78c4501099c038dacf10afd7a153a74ff49010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x80917951e7290ff484f4a02708e8878be9acc532d0408c071959606b664c92d8aa6f2ccc1612f46d0ef436e733c883336a0abde3bc838a2d9601691d06623009	1614170177000000	1614774977000000	1677846977000000	1772454977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x71f1e04da13b97a2dff285347df971d00c07be04766218ae64f4b1c3bda7e5142d4ea04b4d4d35f1cbf1a124edbdd21491beba5999ec06ca5b710c5888c2af8b	\\x00800003b5618f3a03f2c9516d859ad71eb2b70c313a0dfe6f32c250b56edf84d2756941f8367966dcf89b7e4b74b3ea0de5d3a13a1efd3e432a51faba8e3912e99fa7432ddc01f70087b8bd104e9a9f8f5b5bf0e0fa28e1ec841dc0dc3b16f5777fdfbdb40613682162f9079b1e29687e5c853ef40827b176420317412b9cd621b39911010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x032c45ba45d09a6b4a43ca94904fb0734624fa9309d4e23fde0c206ce54f29e86b4da697ff886b73e661c0ccce192b3f1faf94f3fc5b1d9992eb3f8f652aca0b	1623842177000000	1624446977000000	1687518977000000	1782126977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x729d2548e1ca2f26f0742fce43d261a49f99d9242cd47df1708c3cfeb06aa73dc820012ee47cf6fe6d29fba43538eec18dd729f6de046ea561bca800ac6a1071	\\x00800003b037c51f624f003bb7f032a129a4a214c2d4414b71862038ed57bcfd72f3691dcb428c825f375dbcedaa4093e683190dac99e9e89df87a926525bb6a46d1a6595867c8fdc72a3bd65b7bae10d838cb3e14c819562800a4998b1e2f5e18b1af9728a6b6f42d766b0a020ee8071f55da8c2e1f97dfdeb0682c5f1cb80da62b1e6b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xdb88137ba39814ae7fd184b26b9773841d0324ad60e6001d63cbb9cc9c0c773f5abe38464d87f7d804df5824a373f40db0fcefbb9ccfb65fe3e5d53f107b1b01	1615983677000000	1616588477000000	1679660477000000	1774268477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x736943169115ac07571635ac0ac52c3ce388c64900c85c463b5b3c7ada7c731a29f872906d4a43ca190739c625838e24eee5c9ed9e631f220e76f053e310f8ec	\\x00800003dba232c921d9066a1a9b32400dfa2c3a435f7faf52728d9a9bd51cf15067b8e7a821744e1dcca7d01bb49e08550b9b865c5cb09568b78dc611c8386aecc3dcc72cbbb7d72dd05b83b7391f770ea8632d565a9e03e6c33df746bdd6bbd8c4f92c44e5bfa86377f979123344ddf9034dd945591963bb8cf7c37ee212a4659c1c41010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x4051bb3589d3b783c379bda23bfdf61d2901b565ae775010843042dce0b8ac395e25b9d47ccb38d12e60d4edd7a2357f2fe6f6b155878754b63efa142b6d8a05	1628678177000000	1629282977000000	1692354977000000	1786962977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x746deb397de2e6f893fc0435a78af69eaeeb7bfc63300bb731aba13369cc058e0495c95af7f3a65c47cc1c144a4d30e3953ca1252dce4ce584115f13df625960	\\x00800003e276cd979305f8aa4ccc7331d8a44fec7e84d482b8ed8de5bffa9d6dccc24047d7f36619564dfcfcf12ed3df65624c345575e7fb0638c5aef8efdb44a9daa36501aa7979dcf371cdb7cb39c9225ca3bba1793598ee833a67bca68ba30c3fc152dbad890c46f86eb83f20bedab34942fc506b226d034232e6f32f0cff50358eb5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc029f5bd20dc42457a153ef1d34408fd546b654bbf69e0fec9096ad5522805d8d0bd4197737a82daa1c9be0e3f90e58382abbaa675a6232d3b5ed574db971907	1634723177000000	1635327977000000	1698399977000000	1793007977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7459c107423836a86b8a9e7a547ce9dc455b73f61356cc1f7385f8b35247fb31c773222359ac8e90ec818d3ea3ee80f690a2647c0dea2382a1c96f4698347a59	\\x00800003d399328a6003b240bdfc48dc3da0e978a30240882114df81ed6e4e315e4c65d0ce70970bd5a37ed396780fa69c7428c1fdfdd7442333d1895ac638fe7c7917a029e2b04469e00500e1578330e40e1ceb9bdf22e3b5d64d32e54e51c8fe94dedb1b4e9b11b25844995bc2693693a83e3ba6fa36b9ea9104b38e7ac78de03cf549010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf38595b5baada4ca6bcf55f01d14276000f5ee1abfd31e81f9dda4fc82c48af8c39838867a791e19e930e7062c1ae1d1d08b6a9a54daadf4b2cc7b6093a4c402	1609334177000000	1609938977000000	1673010977000000	1767618977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x783d35a18d7ef1d07f70a5cfee57d2b773c50eae6e1b7ae782825607fab45d2e472fd8fdf47167b91e2dd336749873c19190a36b9a5515c520616e666800fb7c	\\x00800003ed0b223fbc86c7a0e2718945b3f8561f90f42e467a842878626c4b0709ec0072541c8a4f19d8009887424ce5570857ddc1f93f756c62f8bdd9e1efa85cef0ed754e0e50168494bafddbabf7eec2517f172660f1309127bbb9f1468e9116804fe55a40c0e22b65f51358248589319baf30b2276b88f2f02173ab91b87d9cb1063010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2a4893e0c2542a528ca3c9650677371fdb6bf4fa9f265dc201dc0ff0fe15a9cebc2f063b8376f19109b3ba0741901dbc059fda3719830f2208b2fd31d5b34107	1611752177000000	1612356977000000	1675428977000000	1770036977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x78c9149a17dca8f9cdd58d8ec1eb5a736e1e9dcffbe48723df0822f0ee263daaaf9ad6b58731590165b076c33dc51e61e55c38dedb6644fb65e9bb3fc85a86ea	\\x00800003c7f6c5e5d472ac50ceb8987cc2b278b7ea893220ea15bfdf14e3fe9157e6b8d9b4f3300ed0cf89063a3bd793ca74297479d038c6701a48133d1c6820af839e67ec06d31f7aa1f973bede3e16a9c30fa5490e8e2e88d63ecb7be644d85bc3464f96cfecb09af18f2448c63b313a1dc27be1d32cfe5368cd464bd2948829fc64c3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xeb98c7afcb052f996870f3ba8855338a88b96fe6d5e4f3f1a48e699ec8e3eca6a0dddb30ec66a931c89f574b90ca9e449ca0c01e57854147027b4e0db148cb00	1620819677000000	1621424477000000	1684496477000000	1779104477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7a69eaf6975aefd8fb736caf9376f690dc7e9ddb5acabb2377ee30528fcac8192577108cccde4a346d17709b2f5d10ffda2366fe4d03e5be7dfd770f6c247041	\\x00800003debf2e2148ad1f768f79a1398f4209f14c0f696385a29d26672e235b6d32490159da6f70d9a29d6c6c4c29a4f48f84081c2c6a569a3381d5feaa627316a2ecebe242dd480e8dfbe88d594736dbac1d17195aa7ebedf790e3ba4cc301d651c64349e8b2c37b8308551c627422b7005a9fcb9fdb43f192b26407c4cca4bf29d349010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x216beb3a3b085c030c21f109f07d5c015a41026655c9f1071a46fc191cde8666c459a928831f290d6970d8e0cc577c208534063178cb6dac2bf77d9be0157304	1625051177000000	1625655977000000	1688727977000000	1783335977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a41da09b051e5b87653b1722cc11df05be28fe8a553a1ce3dcca993e840dfa8fbdfaed7a02606185ce34f1d1f90f632b70280f02482b7e223fa81c4785acd4e	\\x00800003bf7d34a70d184b10a8df0fbe57f81ac84546ba111a91608e693746ed006fbc251c2dc6f756fd24ed7a26057779416f333f6766da78d9e629e53ffd62d05c6b86351125661795c592d9253f3962a154cb4e58c9caca1b73f6595daab41c90e330033afd1e898091e387b66c00dd904386be2649db8b16eaf21a38c0faafa83f31010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbe95e3d34cdb5cd6a70a36cb9f018f6ef426c4de8f91334715ee450437a7187dcd657133eab00c1bc748dc96925a8b98f2475a8528a737470d05907738109a0a	1639559177000000	1640163977000000	1703235977000000	1797843977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7b5508bef890f4e23cc587be6324cb5e5e5bf14d12c440bb20dea2b1413efc01a15400a2d2cd142a6b11c6385985067e0903719465885f6bbc89556598ce9537	\\x00800003d50bee718ba8d8deb620b689780157426fb17d1ade2c6e6902273ddfaa1bc1ac9f6d3b98860fcdb4d88535a94a63273fcfb84a0d09a6db289fc9c05cc9287f72070a42541a5fe9658c0ba8d475f3ca0ad8d95362fdae494964c96a4686edcd380386afcd6584ae914532d75d4feffda4fd590eba56f084d76f26d6591f8d11df010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x68678b48533375491e260ad5f7a2700ef0fb59d7f1bfcfb194704db6de451a06aa3bb1d44a72b7b9cb7358a51ca739bfce9fb906a3637a882b5912a016c47c09	1611147677000000	1611752477000000	1674824477000000	1769432477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e8d95fcb73751ed82e4b2e79167a85f36d92ac85457f72684e4006819da2ba7abe51a39db138ffceeb72144f333d3246ab66007c5b5a7a4d197e6c259d2cfc7	\\x00800003db388da9793f9dc224a22be351618d533bdafdcc0b1b747b5e1e1ab969fb59be94ab040b357ebb3b9d85ba8d4a9e8fc351b652635d13ccbfb4fe0a91d75414b13892eb2df1d33152798cbdb49e8e29602612b77b9843f51ddf72eac573edc726f32ee75644e798fd9d743b9cd36cb3584f0708623cf1408152283f511d715cb9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd4b77eb72bac80730575709ca6904fa99e263b3e6b57d7ef5c50b401707e56b7183bee4f87de7d6637d3a3851102f6b6bd6e5245eb8b2a91e3f415b11dfbc20c	1628678177000000	1629282977000000	1692354977000000	1786962977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x81c9235e86508c8cb3119abea260494fc6d1490dda7cdfa7b651de3e2c58e23190cda2ef3e10395fb1f73be43305bd3298af28abb133ab6adc72e8b7f151bf66	\\x00800003d6d9a4e87ba9fcf5108e415e29a9f00cec1dcc2385ab907ed4a186d4e9ed0929796d86ea72cf7923be67cb656ade5ff57a36f80a807019a0226dfa65f9b40c1e3e81d60fbf2eb1f888a0f6f129b7889f0188ffca9512e0274fd6872d1c2a7fafabef12f90e09c8c0313a38eb0eee13f743b95eb6e1eb6050656b727dee36c905010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x10f57e022e6a9620c4bf550beef4d05298a60aef2ca947087061ffbb79986cea15b0377fbde5c2fa48976a518900868ce25b607e4a99e08284b1e8ca8786750d	1626260177000000	1626864977000000	1689936977000000	1784544977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x857d8d04851dd561c00b9cea4159e7bf0bba352d258a78c51afb9316a12ad088d385a796bcbd693ee926f05851e68dd9dfed8fdcfe9a4118d5d90e983c9b3375	\\x00800003bee5cfae1ab321f85665c401af00f3ccde3a51eb216d14784ab85b8c1bb57f604a6c3b8d99e1ab76da8424e3dc42c03d1c85b8905ca0852083c065f66e5f8dd6bbe8c9acf28d6a6dc6c8d28600a8c43910ea14974a413a86dd2dbbda5d009e26af6ebd3629f0fd3a9db41d7097e58f137b25b1dbeb0ddc27d48ea578a3a77291010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x76191668a72ba9ff678ce40c40ea7e5090755cee1827cb6868e688cedf3c0d6db5fb9406df8ea55be6bb9f42e518f7f796aa3e22e70b2b4e1580383bbed54409	1632909677000000	1633514477000000	1696586477000000	1791194477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x85e154a1d559a029dd8beb335fa19c54487ef250424d7c4d9ca82bb0bf6d0dc3344283e25abc27dc4cdff85fda356af11bdf10577d0daa010d7589330686434e	\\x00800003aa72454fd73d25b12e006ace96c621c216e46830f9b7e68db4cbe5b4ad2734f0bffd61b8d055682c5d824759179c908daec68d6048e95258725d8957730b568c54c3be48dcd48810c0f6b4f20d766253fe2e6ef803fe065d1fd3b15cf27e2683a0036ecfca1dc4eb2dd06c0d2612a89e64000260266204429ee39a880d588d4b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe55c93edea235868333b59195b5982762e8d04c9f894a92f5555042daa020597345cd4bfe26f4efd80d26d3291947bd44e0587ac7a76563073b7e018a2ecb802	1625051177000000	1625655977000000	1688727977000000	1783335977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x86f171c8fb8fcdbd752d6d01c33fc6c62dd9d1c61b86da0dd0ceeeadce5428a66406fd1ff87e8676086651c0ee53b074313066c0f8d733427b3b4d9d03c51aa9	\\x00800003bc97a4b1a9ed67779629ff56db36e28358526fcf5f1ca9e86ca183a2febf06199bb158184244480a3e488b8f90ab4705e4e0cdfa625210df01fc8ef0f1ee275377f18b61c7d719b321aad06de97b3911b726555ef781c55895a360486cae1803c051347ff5034f98be0b42f2ff05aac79a47ac1c059af04c70c309e9ba0e4e4f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x861d7d5aa5d0a54bc35a3c902ce41b005b36b964bfe90b24fea333a1176040aa7f2a0e3b6073007353bb54c8601dd34766e5f7a0d021e3ef17c4b19432bec00e	1617192677000000	1617797477000000	1680869477000000	1775477477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x86253b698c16f18729c004824e057a3a43709e7ff6aac6a2ae1b9cc5b63236ede4982c3df96d29ba173daa466e336f9d73fdca3a5c5c48aa126974f961630f01	\\x00800003b57f82a8e351cd5d8faf58f99b792984f7263f793512167b786babb7d5d9884bc2a79af7ae146941d670b571de555cd1458fd403b022bc8f34ad3f92f48f0b86eb6638c1d44468918ed0723d2c6112fe368bfd1017a3f41aca17d64d22458a259ddd6ddd28f7858f21fcdceba831e99d788ff0230bae990283cc8c90a0159535010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x062fe93bed26b9f61c2f9830e02d64a3e4af81d6989be8ac0b999dde223b2c6c82e1860d91067b77b716998d72f2b7e28bbd54605713dfd5519d937504ab4008	1638954677000000	1639559477000000	1702631477000000	1797239477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x87c969075a4216aedc8c5d07e06eac874e415e0de5533ef60df7d4494672726bcf0555a7a8c4b621d9191534503577ffdc51cb205539390c9f6debb58caea6b8	\\x00800003acb67a9b4a36a39a6117a53d9d39d8c8c7f36460b3e079744e29ead1fc93df06463b32033dd85ae740e465e4c4885c9c50a2c0fb73421e1356312103988a725afa0c41e837ba2a6bd0414dfb82938e6cbbebc268cfe5193644d9126607660027a4d3c208f17ac575116c5ab265f748c0b7e20b0bb646b3fa351335ac5d589251010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb235da1ffd7106edfc62b5fd801b52589144b13187254278aeccb7d824b10e2ca5f5ffc17b2983cc1665a043ba6bbea9b44bea8e5def159d232fefcda9298203	1628073677000000	1628678477000000	1691750477000000	1786358477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x89a9b7770cddaa250eeb760962de01100d2a4b968764db7f50f43309a6860bc8b5092f934cd62b646200263ee800453fbe725df5b85ba7fca58e2d9b0c8712d8	\\x00800003ccd898ccb74804eb7b08cef38fc4a6c066bef94036cd8b64aaf20fc4def73c1acda9d2a83476158757b219b1cab99726c3915be8c806e6c8262abdfc60891152868d5708d04bd962c14f9b274961b40b837095627e785fa4444472a31952fac7a908f1a205fce2ac805e4f1ac3e5af4c804ea19ec6e900cdb5517662b61fae03010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x37536e3b5900436e14b58a9539bda624f7fb7a220d8b9d7971348ddbc1f23911b4683143acbe3637f0f9a5fa657c671a56372d2985c116ec092ad9dcdb64100f	1618401677000000	1619006477000000	1682078477000000	1776686477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8f1d3cd1af4d937f98a89355dd7bed199fd50410a19e5deec24e16e4e2eee10bd0601f98593e977ef93e89ce593c44092da052adbc7155cab146a57aaf5a59b2	\\x00800003d8b8ad369b16760fbe99b09ab23f1e88a4fdc262056eb126c9bf27daad73edc59e6a8a54f1382adbc468bd413cd0d7b38fb40e85eec547b5dd3dd8b516a7c3f8fc42ab68b43dda8c0e17b58f04f9195a09e1e17ab2e6e25f9ff8cf39bc2f612e191c3b5fe968fe69c4e443669ee12e217907c1d20c0a1811e92c5bcc6aa1d869010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa81589522cd18296d32deb8b2d1eb954595da6c6ee0c0cc3c6a4ccca4547f4249f369cceaafe73677371d93bcd822e5711f652370dd78f192b3038d36daf1d02	1620819677000000	1621424477000000	1684496477000000	1779104477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x90ad354eda30c6486c2db9fe0f214fcfff36ad80d378736dabe868b51786fa02fb4c5ec618759a6dcc31a9829d5d7f8997a17bd1babe900227ae490b07f8ec9f	\\x00800003a694617873d657f99b2a8c646a99657b1b518066f1c92baee9403b268606ec8639b4bb9d4afb9f17b7edeabfa0e96f63d412a5afbe79bbb57db663ecd00f4890aaf24511a643b6b46551b511788f97da78591ee4b0fd9aff6f8df9b49c518b19dacdbe14c2d400330b4cecf79e8c58242572ab8924e25f57102c4a08ff2dc741010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6953b23a9068a31b825569d160a8ede55c247b126d16b0eee71e375c9720764f167c5207c77715f51e98d4cb375d106827f3494f34edb316698e2bb90d469102	1638954677000000	1639559477000000	1702631477000000	1797239477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9125eb2a8eb18960d29747d4a92ae80a5f16bbe384b9a67ac282824e5ec10490b9c490af49b03991ba5710f3d2fc8940986812749c025352b472f37c5b300f99	\\x00800003ee41152e825e7ad0770c4db739e1f16771236c16046c238e8667e70b94c9acb3fd5bd9a457afa1a3c5025d94efb9aa824ec24148a4aa6ee15d85cc3e6697afda59766cfed28e6f6088d92a125eac321f3a301a758898997f96895101b07659e47f7f7caf9aa95d58b829dca780ba8c6bf55ad02bf1021fcb5838545801e96d45010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8a2d841158c1027ae987093862c86108423fede712c5e5c2bd56595dec1946ddbdd7814e2248b6ee08e7f9ce04601df91cc19e3c83ac8083bcbf74ac0d43f104	1612356677000000	1612961477000000	1676033477000000	1770641477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x965da583fc9929402b3d89b4dc01ac1e4166077c2ec809b45516582613b28f8b43b5471e6fe65abfc5d16524dc7d3c4dc85d41a58d3ed933cddf99ddf257c778	\\x008000039b57d535d2fc1050204b69253df33292d2339abc4ff79963cc8b8c35bd57d7ae6f18b85041bce8a02c8ebe0624e8905d5399be6af6931d9c56bbee2c64fbd79c71fc59900a70be68a67885e0d53af71cafaf3f1eb06deac5d60cb28c87d3d830b9b4ed615840b0523cf68de0848982f36d69764a562356128b9adcdb0f001803010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1ab575d6a18ccafdedd3f0c66f85ae1b042959550779efac8c6c73369490abaf33ab6e723c6976ed057e1b59ba78b39ee8bbab13e3924b4670bfe71b779cb40f	1612961177000000	1613565977000000	1676637977000000	1771245977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a91ca6e7507370b5848b0383611973aa67dbd957b23e6f380b9ed258ac0382f473920bab8e90059370e50fa6de997af7f1d65d892db210f53f0f6f51c123444	\\x008000039e447885a5e44cffeb37e6c956d8adeba39d2bf3f216298c57098e35d7a73412a715c873f5c24bb8c827dee39ada56793e392a9ea5bacdc8521511cc266b7f443df5a32888b64666f5090eef82147142cca090710d4b05e1cdfa021d52543bd88577808c6d5c44ea70293ac9f26fc22670f226be66321104bbc9f182549ede6b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x57d7d450304d199af3689126c315bbd563486c0a8d6cbaef72db5424ee1611b5edfe9bf575c575adc216b58aae87b393319a502b594a2a4e8ba4b0fbcacaa205	1616588177000000	1617192977000000	1680264977000000	1774872977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9a89d111235077b5c0003b550927e556490bb791fd012e313f9c2cd871c290165b8701d77cf6b89f7edfe29af37db47218fa5a235c01af41d67f2cefdd051ae4	\\x00800003d3c98aa5d54fdbe0ac544fc81f17b10cbd30d54c6f83adcfedf684c6c7459b17d8a3cfe4da53641b221a27929bbc98c24b77d8387c44950df1e7542b260197826717b87410929bf8aad1a0af4f468dfa1d37998006e79c828cbd09d06aa48fabb10b09b8b86124733e5b9aea0a7618238feaddcdfda979d07f5acc7a55d2ecfb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3b18c7e907c17beae710e7483003193f9becb73a096a1a42e96cf313c6accaef25bc4ee47c312622b12e2637976a9db128a89484c166c6787ffd567c3b031008	1609334177000000	1609938977000000	1673010977000000	1767618977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9bcdf7e31293bb55fcdca793a2e0751401bba7077836874d337ee8ecdd4f411ec23bc149b311fd2f371ae4fa2be8254710b50bb87a9a0f68fef5b2271e2e3e50	\\x00800003bfd793595361088821f913e314b59862713aca5fc8aa79a07d09eb87fca4ac1de9f05dd038b4816cd9d586cbb4bacc9aa419b72459a8d80ce71cae2ae9c3fc3b5e76aefb78e0913f4a5c58125dee04e2562dabe84810977c28020e55486cca73ecc53ce73b0bc196c116e5522c9aee6a65fd36cb478a6f325026040dc0768765010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8891a1a6e26b583b0e9ad60f82dc8b70e4312f86afb764ff96805cd149151901c5e3870a0d3b2a3326a2f1f4da0faa9978d8c3d988121b834fc1195334af610d	1626864677000000	1627469477000000	1690541477000000	1785149477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c619f026de1eda0f84a27361a5a9c2030409e18276c94741e86b76d39a8718872b14e084bac3004093cf547b97e03116bb3933724daf738934105f46163696e	\\x00800003d6f8abea3b355639e275b1cae06787d37d9b1bac0dd98a6fae37d418489d790393ed60185c30b1cc0ad869e52cbef0054f7a4d9016dfb7b8eea08883b72ed1a4e51828e60cff66bb7f9682cbea78f2f1be6185ae54a126495aadd2aa1488bbd5bd5be13eab909a07a97f3360d2e08c78473669a974498d6c092d170d72a8544d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0b25898ab36a31606c6dc4c142a5ca9cca6c95595005659f78d27070e7d3a4b1e72b82bcf914a61c1c7d00e2243ac21f3dd9589acf577e0bcce26e62f82b8106	1614170177000000	1614774977000000	1677846977000000	1772454977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c1572fe3264389a841a9ea21ee8a854bdcd7bf46d7ef305fef3d602c3e4873fbef6ee50a0fee043c3a17403d0ad2e47ea66e8c7f95f829705af8527c3fb5bef	\\x00800003cd282eaa31071aa795a8ff9c67e040875d7f28e60f77c739de439664ccc7ee4b376039f8663925ee0817582ca18d7f0ff7d9d55e20ff3680b456200d53d49e67cfb03f315458e59f575858b45401ded81505b408112e3527cf718ed1e49a58b352d12d92c3c5218cf04c7d959a505ac72d54bb624737ba055e660e6c05dd51ff010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x4ac7a3a313b133f18d16f935b876b858429633f9d227c3d862ac5b1aaa441431549cb9d68027187ce11e6286b0546afdb952a04d0da62efaa106a360b44aef01	1611147677000000	1611752477000000	1674824477000000	1769432477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9d1db39b4309be994455219e1700c1e17be7959100d085965b7e4f8064811ba494ef80a0e7541cb65c16a42cd41f2fdc2a793a731c809df699289c7a45b82096	\\x00800003d98b6725dc399469223515a2284c87d17510a4babc86fa444e7aa9a32e130a3a961a9d68259df478e9f068605804a81285369f0bfc3c8c8527bb557dfda3751182b3b64efebba084d5f6d3ee91f215d3fc7503fe638257a015b0158f814fc263e49d5754a1bf5c280b83bcc18096fb7272042daeaa2d2524978cfc68ae112593010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x502f2a80043a712e33fc0d2f7eafbfef61143b5e74f8ec3fef0b53fa59d06ffde0313b29b37278af748e98bdd1a95d555d53f0a69505ad750704d01b5e358304	1629887177000000	1630491977000000	1693563977000000	1788171977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9dc98d3297c761e853e4e4fe3a3d2e2bd9bf6358eca8f6527a48be92e2ef565fa08c67867d6ba7534aed27672a6c730ee25f338f93d91a9b1e5cbccc82369789	\\x00800003c9378f43ce80b926a1079cb9466bfab740b565baeea29abe9cad706edf680ba9abaa238dbe30c43b47b4bd0f7c7445adc4a80738d21f13154301d1b403188d16e46900a6d7c6f923d1855d89984e9b1c2eabcc6473da3213e21e604805632554f86bebd86d744cb76c7f07b8053f80225ea4c42bb8826b049da52c287377c587010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe4d8d1774e0010eaff1312f13dcefcc0ae627898e14539466fe30ffc170b1b07b0a827873df51e85ecca9c19998091c76c8072117de64368464475584dc8c30f	1615379177000000	1615983977000000	1679055977000000	1773663977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa5354b0cd71b0a2a561c5b5620386ebbffda563e980d25eaa1952698e20d29ef221b4b61913989f444ee99c309e3bc84e41dda80488fa65affd186bf91966015	\\x00800003b43edded08b0377cb2886b7e5120185ff349b9ab12a178920bc48ea7c5c00cc7466ec23c3a8bf23169472c1ad8144d93936fcd12e9b6319521ffe5491ea3d64d83de7cf7a5be8fd30f6defcfd8ff6c6930b3e11668523532a65baed637d3773f0ab939dd4f21fe5fde770daa3f9b36352330331dde91df2c58c852a6802a16e7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6a1592109f2a8591da2c2f407bdeef41b22dfef87a3a7788a03a6a9c1e572b44141e32b602e60158b779f8cc23b34e380ed04399a9b9181167c1dcc7bc198d0a	1622028677000000	1622633477000000	1685705477000000	1780313477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa589a09cadd5f20c6eae60b6071e4f1085595b42ccaa19b2d09664196e9dfc26b88d0f53864cb474371e17382f4a64baeb8dbb06d660b36a6ff3c90ab056452d	\\x00800003c608f4b1cbc5041d60b276c91c8297f1a5c284403f42e7df9075445f87ccaed94e455d9981bb1ea4aeed5dfd00d32121e49aa20311880880565ea2a7c14d96de5b1a17e21a54cb21398897fb11533f45b633af89403062211935797aedb00563c3f88975902eb5a1d21d9e9c89605c3655d410623ff04c8333aa03e58710bab9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa6dfed27eafabbae281410c95209c56bd55bf756fe7b4d069608c8ebd766b4a20277bc15cb6fc570e93a247728ca874bbcf66b745ffcf9c4c8eaf81ab811e201	1632909677000000	1633514477000000	1696586477000000	1791194477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa591bca5e63645e179b636129fe7701487b95482d1639571a537ef41ab7552c96ec430ec1a09f9e2c11ee4ed03e1a77b5de6ee8e628b63fb2d46b1efcc222fcd	\\x00800003ab31b1e139aa36eaea153f520d4c10bd7dd0b43e8bd1d14c52518135fc5def60d562b971fdabcbc19421247eb41ab1b1a58901891863dfc1e2156d49cedb7cc0842df1d9d3555b03dafbf1a67414e488453ee8447041791fec70c0c4bdf9a2b8ff98db5f854b30d9aef94179cbf9a4bf8663f2d8ce12ab56b52241e25eae44e3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1309ab4a8bcd20b47631c6c621905c325ff13d6af1688a8e7d40c38a757e88dec120904b921f3faca883b244c104f61ec938caacd9754a75f900f5170c0e950b	1623842177000000	1624446977000000	1687518977000000	1782126977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa7f1b169f0b48777e14956e771672de6d920a5897964e01f337506eaaf72b9c9431e6a544b4d1852766023d8fd4ae9603e4be3f74ef03cd0c631a3722e977647	\\x00800003d55284e267874145411a1e216ed3aab08f938734c836ffdc8356593ba8615b9bbc7995275790d04b02a7621d49a84295067cd0f2eeafb080bd1ee6b0ffd359dfcfbef3423ab57b52d1c6cc260b56d75d219dcf70e27c39fe7cdda9af6736442e6a06d2ff2665bc2da3e10a94bbfe4571d949434ae89fe2e85d3d99bb5aee5c05010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6d0c249c7ee192b7fbf794927378d2903cb6a9c015bb6c25a8e7b44dd07e626980e799f052ad4708a3fc995ddab09ca52b87a014120faebb25644044401cd900	1622028677000000	1622633477000000	1685705477000000	1780313477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa8d51f3c998b6878f37978e71b2df19db570fbcc7abbed67bc31b281952047dc5f5dd4f5f6da733e0254830cfc5abe7d573e97e92a39a2a76f40558a80e7b9f8	\\x00800003b08851f991ae2fff25210420803949f7ba7243b8cd8b4be27b2209299895651027941d0c281cd2cc112c0cfe083832ac44c031da01f3ad127f794c4fd98ad42d9bfd0bd32b4cabf97aa2f345c14288722e9f3d9e1523d4ffb065f7d48d638e7b786ad5c51c2b1436328cfce6d1b750869763821d5cb541a661d74c142c90d18b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x988120b370d0031ae0fb5764525cb4e38cc494daa2ca356cd2e28a5b98b2b7727caa4c45f181f951feb29b02c349aea82f22376cf6d8a422290a8dadcd90e50c	1612356677000000	1612961477000000	1676033477000000	1770641477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabc18fc9815ca43abb50ddae0b63081a942f337d32f831fc0cebc39aeb78cf5d3e79d92b911da49383a52882be5778d6a806a5613f199d8ee00016c861ddbfe2	\\x00800003b4fed399899f443a1116bac1a1bf688276a84da70256602ac176e83ceccb230d57b09e0400535040c3cb5fe45ebcc232da7f44ad3e56d5536eddbbb20bd6034906545e3c1b3aa464662afc314ade8df75a33bd7c4fb0fda4e05e14567d4aaa26ae86b976f8799009950990630891ae61d2efca71cd65dc65f1351f2d7893c16b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7f1bb5e2797ff24ae272ca453624f6ef65f84ec71a6993136f8acfaaf4369f799fe401f665e9760e76143b1a5651301d9c71c693c6cd6408d46375d22393000d	1633514177000000	1634118977000000	1697190977000000	1791798977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xab854c71da4b8119d6b975398f5ee9222a4b016bc68f7e54184fe36a9573ebe3d6a0605899f5b432db8c37f94185e7756ad49033757b2bc3af24f8bcd72b1885	\\x008000039db012de5fd39cf23f9f01323818de6ba464301bcada4305c9465fb51f5f8c0dc200a1d17036970cfbb7842eda94853a3a22091f02bdea948eed95165f80c59a4a7c9e6e57d5ee027b1081cb613d5ccbef0dfe05e472d8d2e98eeefbc667ca7aa1f4510132fac2d64edb84a18042245a4c13931fce8b4e994ee77212469f45ff010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2e432bb1cf7de039f37f26f3345ce10ca2df69350554e95c32e894bed0203a29f50c19113786ac37d0d7523c78487bef647b912f3d28b1af106120bb0889f408	1615983677000000	1616588477000000	1679660477000000	1774268477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xab71604671b6e46cec89fb50c4a5b01401327660984c419626d99084969d16953de2df11713bc870727de9146d6fec0724de9fb1d5c205b92c93b497109302bd	\\x00800003bea7f68f770d8c7140a7515dd7db12a89d87a45407f7e6297edbccfad21a2b11f30bdaffea2ea6c338c1f383b36f2a3757234d0d3e118f198a3225dbf2c592580ffa6e78e7ed5d1f65b37ff3988c05daa8b1fea601056e19a2bd01a3652b07f76c4edc2b55957d883a8fc956390294fdd7fde91901f8119df19cbaa0091fce19010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0ba99322891344bb8e717bcb3b6405a6d65ccd9693cfb900fb080e9b2bf7b8a59c1719158d719395e2098232f8ff1fb69bace8faa49622a2dd32cd839e4b1d01	1613565677000000	1614170477000000	1677242477000000	1771850477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb2cd2b3e3e7e695dba286a7c90a4b6f8f5908301e6223d52876e872c189c58df8650880ee0115df7349474a691791544c847321ad688848ba599e5fa4e2fca1a	\\x00800003dd0bd1af99f41579545d32e7778f69fa6d3ad69c5c40b873d7f094215e8de06c94cdd169bcdacc420755bca08c351c052c02bf3c4fe39f3ff4efe0a9b953808175e7f0612b12f68968ed2659c06c63fb541d0309fa55512466d1126c6f6c6a653dda4ea29887b7703cf20cb63cef2d71edeaf95edddee5579441071d8e36e611010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9f22c048431fd73b097f59d4165ebbb0d1b338326d5ba94001b8bab6c08f0460bd7cbfc1ab3a5f6583e4c3a4e3b7bfd1c6020f2dbeb6d58e38e5e50ab8cdb50f	1627469177000000	1628073977000000	1691145977000000	1785753977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb20912d3244eb7ea776ab97714a75c5c13c85f7a28cfe4d1a642bb6b816a3fb4f5ce2f4a198cba17b889e5d71d542c1fc9dba1074030b487e6beee8adcdbea35	\\x00800003ce281c2f349facdc708058db6b5cdf7b61d76ee42b99cb1459ccc62febcc34f51face0537f3530162b1fea5778e1e19dc39339a0dd34d97945c067db6b74f7508c5ef6225b1fdac6358b921245df08403451d13db0f052310ec420d3e84a14952753033e2cd5e26b58ee28df5ac6b4e06ad7aac8ce7a5025cf293970e7f18313010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa82c5509e0853542248b54c3c078d72707447d483754234b8f15714cfeeaee8656df871290b79cb2e4d93bc074bb6a64a96a2b8f450dfeaac1091fb4ff486209	1626864677000000	1627469477000000	1690541477000000	1785149477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb431c0450a8c99437c5960894f9b867c1f75b8093878a7bb59ed09cdefd256ef32e36a23d5947e5e2e36639892383a277aaeccdbcb143685d5720e0d1575da16	\\x00800003d34dc96eca40c6f11190c521851328552ff2d4694a0368b233a5681eb44a44ceac449e4d249672027cf231b7a9ed83cc0841cd70ae512ef5137ed04726223331e29448199f2fbf827b2da94ebe9c7552f005aa1aab9d8a800303493522deac7e9f76c10139a5712615b59b243e91545f6e2701b3be80de51aec8f586988d7c21010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xed20953a1c923bfe72cf6c1644aa747fa71d925a915f3dcc4af70c8c1839f1296e114af1940600a1a16ebff14c11b224553bf9f626368a1b00dff7fa0765c60b	1629282677000000	1629887477000000	1692959477000000	1787567477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb7a98a72900f27bd77c197a77cde2ab4a64d38a84657e20d0a4fa50358c376a587f0bd8355cd4ec1559b2e35e90f5c20c492010dc6b8038faf03880004476fb9	\\x00800003f4df5837c501de011b49f2be134ffc1d21b64819f94ae8e9a98615b156256fc82459bfc72d1fb433d62f01f88b780f5fd8ff28dcb2900d8a70fd365419d00a1a6518bb1fed9ed95ec0a210c3d17ff47a6a335191e22dbf2ab5c968ffff6224758ee4d7e6503c29f81cee159bf49e9e80416e4ebd02954ed0751a584be22fb519010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xafe8d1410e61fd99740e7588d1c7b7d67d9f1f736ed23f285807ac9bce8794fe0183a3e3380e9a21f7ee83bf352dc0b93f3600213a6cd3db3e6bb865fc410206	1616588177000000	1617192977000000	1680264977000000	1774872977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb90169ee54d6a069efb05259c81ecefcbe1eeb31ebc7ca9214afe38323195c411d6b3e9eaa1748eee673ec98d836fbff5ef6c2ef3ce48cc7927383af0bb48cc2	\\x00800003ee7dab4a003614ce7944a0455d649e4c7a0ed0f10a1c1cf6fb92784b9112472589f66aa4835a0ef8e922f9151672b79234271ba529d0730e14aba892fac77538f7927132a1f1d748ee41f711d534bd942f8f98b45025d677c41940a0f57799194a22808a5f270b955eb0068b8b6b53c1e5785e36a9222779dfaff1f884f53eeb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8ce43daa5f5ee945a6a2971c9d0233a7e57767ea222aa0b441ec3f126000028bbe5ba1425f56dde1e245dcf248ea451bd87e7ee537771d38d8253bbe2630290f	1624446677000000	1625051477000000	1688123477000000	1782731477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbb51fd3cb80d2856ab316f5316f69c208d3db998a84d107995f11f1561ec65ac5369195a8422662a85ca99acfbe007e201c5e90c902b250432e244615001fffa	\\x00800003bec77dfb0edc7bcca041cad7d7019767d7c86f1ab11af3d6ffeb722759d760ff4afed5a6a5aa654d3254505c68340c57a026fcdcebabddaaa5b42202a8d3923361048318070753a78aaf7816662eaeae677065c9697eaa7908a631250b25ce786ed0a35ff4f255597a4e4b643a0c9d01ed40fd91b56a4f3419ffba4de9db0047010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa16d489bfb36361ab5051b0ee42eeab12a66709b843250b233254388b909f620c951f726418cb66d2b5fde64c758d68a5977124ce8b39432c000efdce2583d0f	1620819677000000	1621424477000000	1684496477000000	1779104477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc16d1a8eefb91f1b43a7d54d5751a91993999f5e020458d441230a4c7768732cd8d3c146a7d7ed718ae04638cd161d1fd6101786d2da6cbe6c6aac8d5cca55dd	\\x00800003b9244fd1dd0eea2892700614a0bd7e6344911d388195f57af7775b7cc0971bb4a08570ff42db94cd03a37accf4986021df3fa96b33c51187a4cbd5e38a7fd93ab346c5c1e33b258f308e95b66c958300b7e705d101ab1be80902cf8bfd5b2fcdb81b1b77fd1d425ca9e05a1365e3bea733de80fdf343e51fd4aa5d39ae5ce1ff010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2e4bbfea7920c87090ed7b9187ef723aca3470598055f962de6e2b0672b68dae34fd2d9c029c40b16d62d6b5b84fff3192b44f5b9a99d697f3ead8477d6e0908	1619006177000000	1619610977000000	1682682977000000	1777290977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc161a664bab0295e979fab239f8a0bdadceac839c012a1d1aa340d38099dbcd4fbe9f8f94f550d04cbd6b4ab85b4d326c515d415b03e7d2b6f9e30c7a20b46a8	\\x00800003d5caee1a829e809536c218747b052d00b4362597339ed0cf456e7318c18e161cac2665eedacdeb4fb177ae43d0717f01bada23728eb082cbfe7b3db58a115895ad7aeddd92d5891a54353738b6c04aeb00bbacb7adc82b3f0707aeb6805cbcc3e2eb4c85dd5c57eb397ed5fd5a3700241c572b97f3a9a30c8637e7065ffb05a7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x37aafef552e4332cbc417701400d75793529c3dcacf46318319ce0f8c4df222d20603a9c3668dadfe5caf9954ca763c6d1296d6fb1b05a89156c70818856b804	1622633177000000	1623237977000000	1686309977000000	1780917977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc131512b5fb75e1b3eada84eb2aa5ac8f2879f35caebaebc9c1000f49e7a5a42f837f94ec82b71780a20206520d94030c01649d599cebd1a81dab8f1a9bae2d5	\\x00800003c4e6e87a793093dbe7f13cfa6a2d6edfd12edfc505950e10b77b7058b777c31518bf5c22f00de9040018392471090fb0db4dd8d9df5987c966f739338b2e088009ff5adc58ebd26c930bea117e66fab3145fb779e5f4fb4f4c40969d7688336c8c932fa8f818afcc1808a732cb53bebcc725e6042c6d45b655edcbbdbd30c2bd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8ba520d734d5ba5ed28cc47a089ab22d432bb7355e596f7885d080ee2486f2bc6fadd7f901cbe940131d9fe188fb1994f6cbe37c4b54cc91e69c7e20479a5e0c	1626260177000000	1626864977000000	1689936977000000	1784544977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc23143d3006ea463e8ab079e4520615ba69823ca3f5c0b4c27f506a2941358a3db61751594631aaceb451bf34f45cf425117b4c15b023c165c7bf7d005c099bb	\\x00800003b5e876a8fd646105ac92dfb6404cfc5c6c7ca80579495441c764f9ca15c9d75e1c91874b1322e2d91ca76139c737bda0db772b6df7c2cfaa6bc339db56b67d015a5ed6f0f24c041d937d853503d5d6f06d21a0a8f40d7fc40ba45a289bf017128a6b52f22ac004d310780e2a6c459264f44365e37ce854345778713da6eb1cd1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x4f2760937cbb9c14e10925317a2f41d14b8425af7bd22ea554ebd196e5b577bec1ad3a60f6ad47b37ddcdeea5db43ddb772cb4b794c8b1e84109ca4229336107	1613565677000000	1614170477000000	1677242477000000	1771850477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc4a540d61a184f7bf9bd5a164fd096732ad90fb0765d022e2798d88046cd5daf4d3a30474141427fb6e12610700253ec7814266c0f95103dd68b01229f384d62	\\x00800003d230694b0ce77fdfb963a7ee7182581a8563db061c4342dba507faaece9460f96ddf7b86e35c679289949b16923f6ef760cbef36cbd89f8c0a6a43d29f35f6ef3d802302cbdb3ddff385c04724ddb3c6c0ccf8ae1654c0b4d44fb835add3e99e2594ec0a021ef4b9f079a8d1b70a536253c6cf35e5d81d6a3c5b6f0bca8f91cf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6ca6cb53aff631a81ed278e45ab51e42f74dee8a6e799c2343d781c079405bcd49be9e8da66dbc0e6015337e90adaef7657fab366803381e3d33bdf585750603	1629887177000000	1630491977000000	1693563977000000	1788171977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc691698ede27362ada6e65ef67e0ee17f6985fdb60c4d1d41abe3f0d0edd0ca096629a42bdaf22d491f8cf48a48eb747d33b5db1275617607b4ccbf1efc35061	\\x00800003cd4b19c41e79d9709f77e98cedc00eee0f805ba9a46cd4e809c73416f37ae50a054cbe71cf4777cba49b5661e4f2f3c0b74447c949be16742e64512d0db64de8d4209d1c69719b326b3f8fb49df71d39a8e03cac277b411f520cbef9199c11d4efef4647f77f28a49244dd3f99bd07d7af6baecf23db93a96924abfe2e4d112d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5a3abaf3436e11f09c3016a22dc6ccbba43e5d41c67cd73d186c088ec4ccc47a4a515decb8285bf6bbb4fdc25e18fb2b1968a7c6879d6a6d970b51b18e67cf08	1623237677000000	1623842477000000	1686914477000000	1781522477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x00800003a02202ca6b77b47da9edce278700f22ffc785f4a4f11b406b7ddea3bda358dfb5c5736be8b8eab23dbf55e5bd5ada7ff97e22ab59613e1f8f73310d2b9e3f2c0e4bc98751c847ddc76024d48ae4c69967ffb93f8267f49494baa545e645f14709309b8a5eb347648e5ad6eae5f1a52b20ff3ee9f730d3c086e83aacb203775b3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd2efa18415215f472fb1593b9d8a24f0354105c7c9d0822de89a7f9e00bc056acb65210979a4c9a4e21ffcb4928fe0116799ce1370c6dad5cd73bca94755ea02	1608729677000000	1609334477000000	1672406477000000	1767014477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc70d5971a45bba1deb00b558725618618735b97e5684425322cac129162e44149b659bb6079bc784ac5e6f4af5fcb19715290804d189a3ae06facba0a9357c63	\\x00800003c6adc6bc59f14bae6195f884603681f41d67ba765961f6a9be3d790f57224b1cfc0eb3824700baf018ab4e5e59fa47c81af6b986e408af880433d464ae4f36064dd9c575a0de0013f8f67514ac94d686b7bad04a5567745635373d61df6b0a6796c3670ae5238edb7f0459ab2d150d9a306ed01770caf2e9b9b9c478501b0637010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa582010acf54ba0eab1dc0e8a0f78955652f22204ec40018aff0eaa4cc1afc25785df80443448b34e780a1576e347f6c0af71736f3bf31868f6cd867a4cbfc09	1623237677000000	1623842477000000	1686914477000000	1781522477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc949aab8e5b4efa6c4eb69dceba37fe0b40f700cc61bc9be30ad3c2f9335fd2b7c0a828b6e898778a431c2726f0a01f7886057e20cf1436d46ec4e38910bdb28	\\x00800003e880674f8ed17a6dfe364bf878a918d638c52a11e27e2d718f4e0236f2e90ffc75563ab4c9a83ee45faff60b684e1c21933d3ff78076cd8a650e1e646bc1d54f50d489319420fc348ff78ce1c1c3d915eddbb97926a87b9f492ff4e1f4eb4d05f5dbb4bd2bcf8c200e8131fb4f297401eedb5d5873e3881a033ce69de2a2e7d7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0e2fe46eea5b885223b0963bcd39b1c4d982e857fc2ee51b29a0777b1d85a59d3e7a322e41bf82230769d22218769837f32100f84aef84177e065a7f3bfe960b	1638954677000000	1639559477000000	1702631477000000	1797239477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc9a1adc21d3362bd668b16bd31186999fbe2ebe36e48aaadefaeecf794f6756051d15498fe6b75326c66f61f5f5874aadcd14971752b857072e294c813023c95	\\x00800003bda6aac7b04d0ca7ff3e1974b30ffd06555e84bca78b2100b995c1aef6ae4448605374fc91933ef8ed7fa4c2ba89736c28b10187d152363633e3ff1867694aed4d51c05de6b8ac8d73b944e4bf3e7077922a31de11b48afbfe2968a666229b76fe9d666e519165ffe1764477b8a82ada01098df41148c161642306abbfe03607010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8e40ce4d3b5577bfe6cfee203c2a05d4d560f2be67e494fa1afea5438af59996029568c7457b8061fd3cf4f1d13bfa0e66dc8da4aa76130b6969f3fc4db44406	1612356677000000	1612961477000000	1676033477000000	1770641477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcaf1f1839c0879151538f855ea7c7a997e89a2337a102e489947a0f47fc124cfebd689c8a2b8909ddff9db07dfd5b39663385d8f5cbe5e8f8cb7f16a88b96823	\\x00800003e2d918b56c39f4fb2e6e7134b80be83e4a63f44c4aa59427c37601e19e4a647be529bcff746c81570643930b08c2d5910423c2fd24155fa04dc05f91a146b2d2f8c581af960ba78ddd86b09212208c060fe0d74c0821b4cfd67b2973ebe5df5b069fda4aea5bf5a3dd585ac5def41077363318762596fb24820ef3681d94d6e9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xadd7b809502d23543656b4a5f60649e38ab7cbddc2e0fd6e23d2afac3a9ae40093226da5bd35f8a61a1bfbec02fc614b0d5adf6ba501556a9363f75e2d815c0b	1619610677000000	1620215477000000	1683287477000000	1777895477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcd01bdc1b46dbf2f8bd86e1aa2214a082b53fab4c1d37c373202282085ccefbc1cbf5036f441ec9bc1459036976f35a7169e4a2eb75844fd2cbbb5fe10427b6e	\\x00800003a458a4d99f88eb1d4bee671ff351c9953dab5636ca28cbc6faa65e3bb4bb0cdc64c1c74be8b64287fa3f2d8dcaf8563e21788168895a6221e965c0f835f2b7eba638a1eb445dd1a6fe548b36531683bac77c167bba5422af7339732a6c341260456eee28d7a309ecb65b61c05f1e466b82cb9ef721da615260cedad806cf1175010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2ea027b80e94a2d2f8783f79620f96acf9e9f394a027595fb884bc664ec2c0ba13a5dec412deb1f7c17bc954be56d643a15b266879b57d6d242ad330c28ba602	1611147677000000	1611752477000000	1674824477000000	1769432477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcf4d30c69b64be4e374ea788fb80f2987a93963f7a1e91b7cdabc8488332a40cafff8385f7654e3bd2d19158558dbfd24909ff9d53120e53a47692d1434350ab	\\x00800003c806bbb64535febee25dc230f51e912e395b84522aa2227bd5d81bb20d90011059d62cc1fbd8986f013de78fe436820f80a62473dd0b39b74a931c497f6849a855bb37dac49faa3792d9085de9a00e0e995410f702583fdcec2c1ea49636282a00263cc24982f5a08576445654054869baa19588d212622a1cbb79de2ea2b18b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc1fe67d56ed24879695dc277c5a90d2eba7c85fab6f5c628d644c01b871e0f2f6c0cd3d573ec219f434fe24514ccd9c0bf0402b4da02f4cf4fe493d24c56b20b	1621424177000000	1622028977000000	1685100977000000	1779708977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcfb1e0f09ebc66207b2eb60a163a6e8576dbd20f5981e4c7777ab26144183d84b742432eaeb76ab91ceb17e0b047711456f485cb5618240a17a6eed541ed0b61	\\x00800003b54ff8a87cc102b6377893ab26f8cdf6eb463dd27ef1243f571c8c157781ae89ad5d260ceff018cf7961a3932823f7dfe21afbd4b061a5e8511ab0bd11a006a6081c4cd8efdda4e5f03e3ff563d347888d4ab77d54fafa4a45f0ac36140b7f6486bc9140d9d8fc6f686e1442b93fe1ecc49afb610cb25c8c6a3e79249c0e191b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe55f4176211926c2e373e983b0304e47e047976c3e6375b6a4b2f59eff9cc882ce697fe1f06d50181b93d9238dd86ea00d29d2b36702477f440756fe50ccc00a	1632909677000000	1633514477000000	1696586477000000	1791194477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd461c1e750289a091292980f32a8acc27a43b2a1f1061077917b5404440cbc8a577c762c1007a8b7eec25f4eec9e68832dc2b4f46de61031060baf2231b49f31	\\x00800003e3c08b36c8d7ddf73fa70a57fdc5f26807e789279fffadde28bed9d41f19c1599b232b9cc0a3db83c0fc0dfd6d07683b2f52258acd8c26078170aeb047b0ff221a56b93adae8332e01f5470e7722fc26c66edd433b7edcfd9f1558e7b4ffea8406bf8ff4ea38830d54764e17b862f89dc4f8371d355cdba244a15a737f88b98d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb79abf678040b43bcd8113d4cc9e534cb2a1b0e429ac3504bff4676c5762db1c41e92bade6611559e299a43282871fc42a9f28fdb479a4e02ca8f71b611bee04	1618401677000000	1619006477000000	1682078477000000	1776686477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd98d57c5abf73112ab269ed1586601a4a9c6acedfaaf17024479f8179ab5f2e5c7d348705e89cb0b36fe839f62ecfb6c68ed8f026afa9b3405f6683a557b6772	\\x00800003f2d53400e4197522499c69cbbb83d95047854d05cb86d3a3691a460111474c5e4943c1c90e4cf329467be11bbbe964994e5d0896ed9b95490e4ec437448ebc1417a1467bc1b8d260727a36ce182700fcb2bf8e6c71792c92d5deb12bf63e5f5231691e282137642b92238fb19194f8067c4106bab13c491197bb31b17ba78a63010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x669d3feccd36895cb2c85ad9733961b8a2b29441350dfd073e6e1f076382f52714502f2fd3cd5835322b290e45731414bc257c13c222f80cabae8c4f0ef35700	1631700677000000	1632305477000000	1695377477000000	1789985477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xda7d2da86d856c17bcba6650e090ef810a891fd358f5ef10e429f9e9238a8dae805e9520c1d9dff39fda555393f8697839bc0aa35068f0f76ccd5444056eece5	\\x00800003ae885888fcc684553edd3c5d275f08978e841aa6e693a588c8ff22a6e1ee748ea6bafb002519615a0a9cae09f8ae585b44e9180654ccf1f937de96b11f3cd24ac290e1f310dfca38700a8e5570acedc2f9528b58a360b1c7c35937e96a370cb137c45da4c0e40095351ff884d13bcdb010e66b3d0ad5190cb3bda482e7d24045010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x4a4d4f64c3ea31633f31f7cceea0754a9f37341e868bd1af42ae7f583b3b53763978d9d1c57776892eab8c5525ac632f20b06325fce3c6e47662a564b6f0910c	1631096177000000	1631700977000000	1694772977000000	1789380977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe5312de7ad16a29fcc9bbe3a7d6fb1f62a8fb6bc1c8d5010574e73743885068ebb753d4da9067624640cc0b89a0b1570c27a79dcc7280ecef45ea66c0cdf5b6b	\\x00800003d1b507f5bb973e44c36c6e1602376b8837b253fedecf4117f3d1df0be43ded0baa41b99487dbbbe918d7022fb59cc87efe62a1ec561511068fd44a48ffc37f880ef80171c4c1b076f7201b5726212c9395ca34a728573956899b14f48362d95ab373555d197cf6a445c2cc80ca7be8747e64424f2a1d50cdbf43c4554d35ce51010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5e4e860e73d22964fdf9b6682ebdabe3a761fd3209fd606049208e5590441619f48c36dd116d782b5b2757c65f28eac5100e9099d51dfeae2d16dba54ce44e0a	1627469177000000	1628073977000000	1691145977000000	1785753977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7a9b41a89634f92b4b3f7f5ece4ecd9d0c3caf76b13a81297c254e77c9127893621a49e8771e432e9c4ad0308f9bffafaefcb005ec8ccb4fcf48fb306656834	\\x00800003a21144b80f90e17b62937974db360a6dcc109c1aa8d605c0c393000e1edd8abad773b8f9e1eff48a30d6b2b339f05a6529061f0a2d428653911f2793a5f7cb63cef93341fe05676f02e4234c321e8951205bdb83f513ba9578355ce7dee552939332299929a782fa5e811a48dc4308f76af642ec97fd7d528df50ba05367e0d9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3fa8a4e287a225f475b47cf63159c2e5d5c2baf1c84febcb874848344da12c2eb42dd6204a325974f00efba825170b137e15cd009aa4e3a5ecb02ea908d98e0e	1623842177000000	1624446977000000	1687518977000000	1782126977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8559f87541171e4cbd540748be7fe14c01da57a1d4e69b8b89f1c2d5d5bb496964a6196414dac3b55525b7df22f9054a61791ef50d3d58ad678a83205fbcc56	\\x00800003d8bbda33676be3d303faafd5dcef1897b4aa3d57c5441151ee4bea1c78573d909fbaa532fe089362247d8263c9f31c6debbcea6cac15c9deb41b011c48a82c58a23f1992625df28e53833b57b9c105d31f1d7623c37994ce1485df63e89cfbbab2501186ecccf040fafda05bd0353a45fe055d21655a243e7cee3dc8f003328f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc8b126125e1af88163834902158966f0c4ce71ea875c2362f08e051871711615ecfa3c660c1bd3be9bce4a34f20f00dc9656a829daf2f2734d0f102154987408	1619006177000000	1619610977000000	1682682977000000	1777290977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9d527e60a7036b070cb4028679bcac31ebe7ba23083323d0f4db645f0b266e3a18f620609613c340ebf05eee26a9f269a3acfe16d74343120f0a57fcb81b0c2	\\x00800003c879e3468937e4b9aebdc70ee858bf956a8788d824ea3fb01d4df5c516cfdbd0c5c4803ba13065d723af814a8ab0a01cbe6a4f234fe7ca24c3b540d398d3a0075efcd03ef9099de8f916398b244ff5813f9dc1308820c0f714da3711a65cffec2d1b73ea4e5cf914759fe1dadde532f191ec803a81a524fcc4e9b76838551447010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd715a4bf76fd0a7ad44cd2f1ca2fa1c8b36a1ab232df02eee167b694d956bf3c7b571c3da7065243b1bf61a935dcff47fcc45821e1ab3056d50f798f3fc04004	1614774677000000	1615379477000000	1678451477000000	1773059477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb81e507937432f24ee1e67cd7617764a8fba54328ff0d56afa58755a2d6eead40a17a8d7b9339915e589e2ba082e1548c32e5ab7e0b6a7e422135c1089113d4	\\x00800003c4f0ba767daaeb972b8564e2f5cd6fd2db2aa2ef05df0312f99db440e4958fdb4eed5c706481c63df97252d5c0024f5b5f2d4d1d689d37f81a956941ab152a73a83ff1dc3411a11af16eb3d9b1912d44491b561994d1e8825c1ffe821f75c7ff0c8d1e79d90c4e377968ea0249a48b818e903016792ea019a2e3d39f2a385811010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x15709eae05ca05da76afba27da275da79eabe3ab03ab1d2bb3318fe03858fb20c49cf7bd2719a9bf85aa437a87238c97801748a8874803e3a3de8da240e2a209	1628073677000000	1628678477000000	1691750477000000	1786358477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xece17a63b27b4fa7a0ba6dc5cf023ac098627208afbacf3114404412b25f3fe37746b7e09c09e3d46bc804dd4bca604b8ac848eda147f6ad9e653be42de61d50	\\x00800003cdae3256f095e4819e7a1cc9a90c31624e9c167d248fb353bab6a5446350ac15867fd471e72966bb18b4441936a941a82a9953965895148669e6608787d3d28b0e5b0f15256190aafe4712d0b03af3cad957a231c46f64bbe99333100fb880aa8fbea10f0a95af6720ccd326e7d270f34812edf93d3846e5aa11bedb11c50787010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe386a935886215b7813cd5ae6f3c2bdf414f6b6341d8f2a0bdaf56adba20f82b2e73a8ea220de7a352b04a8133c056b119de1f5a250f86191e576e7d9a14330b	1609334177000000	1609938977000000	1673010977000000	1767618977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xef4d73157467706eab4e7263166cf17b7120296e6e6f85c791111cd104fca8f9b059ba96adefb6b06ccba9e639d7ed59a037bf835893bbc390ed4964b1f7014d	\\x00800003a864461dd49d12e2a2bca378a56df7c883b4b862df519f678c95c1834cbc78bfb75328b00e6908a6f5f0b0a52a079cd230d0d4ce4e45713be4743a318db84f3e62e1d66b184510c10910ea078c1a1ada6ac3f482460fd3ba15f2345e8c68845d1b1a8e763ececcfa4ccaa4e292e2507aeac2416350f67f9d8bfc99feaaeaab33010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3b932640272bb9fe1241ab96775a6e941337f0f48d9ce536d93c5b98e4406d02ce3b01085a371cb9d07c3bf8028559b628af88b2296517e29e43f098fc095201	1610543177000000	1611147977000000	1674219977000000	1768827977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf1511f6d688786822bb6d1a776bad03926f0a835a99aad135342be3b478de31ad489045b79ae3720efe30f10a3818bb00de0e5c50b4653d47660c37836cdb375	\\x00800003ca75e00247990501d4df6fb949f132373a5b58455270469221bcb36f004daa567c71ab89c79679d1099f442f8d60f132b6e302ee92ab11812ed294d3567b04e575e1fa6188ac23273a730d5f0490e1ab058a047a56902e63b7a58e83821bb802673df2d26e0a81e3ebd881162ba061050b327f0547b1c2442df702021e696af9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x532dd69e4a5edfc8b9f22f182a3eb1e6667005b2851049b8796dc11689abac830dc9024e82a7d7f9e41e4702b655d1fe8f94520e927215e0fee778ff87bff60a	1619610677000000	1620215477000000	1683287477000000	1777895477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2759ed22c63646b9a3a8f54bc8cd67d780f86279e1e8bafd33b4c2c467d11ae88ce76ecc49cc1c61601f4a992bb70add97b47b8e11be7efdd2083554cbda870	\\x00800003d8dddbcc8505bb5f6c11e9bbd55a55476d060f877067cb112f76bff6035d2f55c3a3f406ad911dab54e247046db2805fd7b8582735c68b27adb47fa048afac8dd1c9c93fd279d01cef0178913a5890e497c51d7796a7a9fd4968e15020dec4832583b84412a981d54b9aa3860bbf22a2e1789c1bd318dc0c1c95d1527233c089010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6f15ff1372f4b0f8b072b3425d782d4a4da553d596f1828a66ddbc93e0b35152ffde8db87e03c127d3fbc30f0b3d031c58a7fad7ef878c7448c490e64f45eb05	1631700677000000	1632305477000000	1695377477000000	1789985477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf29da6b140683c18a40dc96f4dc510408c844a655598704f99eb231ef482b78ca49f360b7e4cef8d17846e2d964d4e9a3dc3863f7b6fe17f16e7eb0c8e8eb639	\\x00800003d2fd2816c64d210a3a2ed8aabc173407aad6f1e1335fc74418a07f70f9e690f89c55dc7efc662a2433c91244fe6c5c3eae29115456702d3d2c3173e45d854d19655793e2741fbfb05dd73df0dcab89af68b688b304bcd3125f7c8ee1935c38c31d69195ce8f93d254b694379ff563c98c1e629dd5793443c35a8e38886b7b1c3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7e0426a11d9344b4e329b0ea32c41dba887cfc15780cd85576547e54e7d617798c603195bfe2484e5a97c65b10e34442935220b2b0c3ac469209849375253602	1622028677000000	1622633477000000	1685705477000000	1780313477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf295843b9b94fd9f716e16c2be9c3f2022b2a67c931de783b8810623de9ad61029c7b8339c1a54c6155f0348f57c96ab7d63aa6c1659808eacfdb4d2521e0d14	\\x00800003d04ab18694e206ce617be28f1646282bf09da3c0ba80342f07a7f7f3c9a106e796795cd304afbc1504f8dadded8d94c042897f2e47a0ced436be7454a45ef4503a0836aaec9162564a50820dc92a997c7e9a553058883a5e347dfe723672add812313821ae71fb264a7679f01025d4db191114ed798f55cdbf20649ee2320911010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0696bb53d9e78fd83d609f33910431718eb1b60bdd0f29a8508e49cdda6e5484dfc0c74e9a08e6faf772376a2378c7e32723ef5c671c64c2946b5ee4e28cfe0f	1611752177000000	1612356977000000	1675428977000000	1770036977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf7bd6377d03fb2a0d00d3b93458083b58652f8df55a803494705d97ecaced9e2a62abbbc47aeb8b4fbaab480e36412b3da570524cd524735fe210b09b354eee8	\\x00800003e476fff98e9de18f04be11f9c95fb7644a89800e24ea339fabb908670a6da48a23f4c6f4897fee3042062091fd4e1ddf4999e548e9facf60b8807000b9183b82691e1078f0c0045dc3fc4fd4092db7c370f82be42661d51b8a8391c298825c444ab7500f2cdbf20e9484ffe8e13d163845051072db8300383d18c2af312f8d43010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xebe25658b01d4d3fd66a35266b587261a8452ea600a4e03b0ccd283bd9ec07e8a761d508d79bc6f90cf2768beaad9d14513a5fc7a8085c3625cb2f5dc2a7240f	1620215177000000	1620819977000000	1683891977000000	1778499977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa3d91a452f4fcbd23324645eb6dddfd15c0fe6234d970956ee18d6779c03a7bb1d5af04b79c48b4e116154522fc82c806cee135dc2138fa841b457d77a646ef	\\x00800003d25a476e0fa8eeefba3d6def61cf9f60b30485f8dc4d118a915f8739daafe92c212ab524e6305eac8dbc15161b666ee88a2981cadb8320c8bd892615bf4bd8e34b2ab6a8595c41e52a651595ccf60480c45e4c5c1d8fa620c3c7db673abbb6b0e33ad36e173d7212cc1ff38c8cb18683bb039a99898377457ff50e8a61f68f3b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6351e4e9f0a49466ab657e5615d4fbf7ba60d2118429d807ba6206a02fe0ccec40fcbc0ba6bfaf57a5f16239418912d1155a1ded8643a95ddcb4edc549653700	1628073677000000	1628678477000000	1691750477000000	1786358477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfa8d407ed5551d6eed84e21bc69f8ecf2fe73bb9e6eba7e386758e3b4bf7308dd7da5df4c13c5d506629ecb8f9081c192aef018953eef34c171e05a42a94baeb	\\x00800003dcfda18318ec292585c5afaf7e98831ed50e24559aa37f16eef8484866a194ecc9b4aeba92400dbe0bede2f280cde8c1528192abac1e730ff7665e7f719cc8d537d047522f1e3d167498785a8381799e40a8f388504d38f1339667901bec94c4ced361eefcbb8615c502b07b9cd73bd2eb6cc6f9a074ecc88dbb0e9839192ad3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x846fab52356fd138f7f086f6a95ccde05f1321d08d8352fc5afa4d73635afbb5efcd2fd5deca8d98a6a767fae59a36e21c343fecea19ba9c390b510896338c04	1612356677000000	1612961477000000	1676033477000000	1770641477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfd996269d7a6cedbbf381fde9317d426f49df9afdcd84d07f0ac6db9155902cffba5a01769a18d1c0894b0c160bbbc16e9fc014dfec8e438f7ed45f8a1c4b0b7	\\x00800003a5b67b8b4733945a40e8dd916ac9731a18b60e0bd09b438e56644b230478ee7357957619bc5e7c387d321e5bfbb00c924928bfa1e091b9dd219dd7918ead8157f3cb46651ecbc595caa1ff7d300ac1d857036c46c0a7bf18657434f7754d7332e2a684633e93bfdec6ac61e143de43366189f1ba31dba5eaf6dd58372554f635010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3062aa4152bbdb5716e2fbdafbb4af62e3bae45b5d40d62a0ea672f390ef3dc8ec4acd7ab9803b23a9dd02b513b9d1beae12229b92ffabbbe54e19d1afbcf40a	1634118677000000	1634723477000000	1697795477000000	1792403477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfed912a8a29b8329d443e4a4212f32c0ae096b938648edd0c5ff151ec1b9a15fd26127314e904e4aba8fed84649a9b6cfdcdda6e493ac808fd9a1891ad078ab9	\\x00800003b6277a1c3a062eb2a1ddbcac27da5ba02f461f0e029d6e38bd39f6eee370ed64709b312c2d263645800d876549ee1ec90998f4370bb2da79a0bc8c4d8e0c2835f9794fdec3ef46a6cc565a142d303969f7cd0f133c967a3b5f72ceefab30eb24add072faa7072502be2f4d06b4b5f74ea29ca6820f0e1749f3de2bbf654bfbe9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5f58b7ea475e75c3d47036a758957d1a0cd06a7ff77b144fe05446dffd0aa61a3de2143d5a875794fcc5cf7f42311bf426d9941ac924eb8430a916347441430e	1608125177000000	1608729977000000	1671801977000000	1766409977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xff4dfc62664fdb7563ac7945c9d4b0b181969e67ad6fd19ef73acbae44815043f1320d2e76d87c76c5199bdd63b4c76a704dec4bdb7b2e8cc5cf951289aeff4e	\\x00800003adf610eadc9cba28b31ec8dfcd78bd898163f7cb7cbd0a2ccce661d7bb274c2d8eb205f8a79eb59ef89ff371eb42554f071dc4da20eeb0b2975523f80afbaf41f9a092af798f33a666964cb037a296a0a7148a02e87dacf04fe6f380e49138a40089d16b11bb934168d2cee385792a3d21abd56145cabff769d6ca6f909767b5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x001582a7a90e82bab63d0437ac87c5199fc67411c138d4f2e1c973d14e2c681591081a0bde8b948c81897130cbec35b2318fc2d807588b5161c1480a4aa66c06	1637141177000000	1637745977000000	1700817977000000	1795425977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0056b4ed7c18d34618aeb53b8e7b91adc21fbdfe1e003a62f25888e2b9571a7547c895ca21156baacb9234df7baafd1f089f72ba0c33f417510eb23c7abff9b4	\\x00800003c9c8661eba45116bd27e76424b646bcaf0552481284e9edbed785c548d02d7a46c02e02f7a523e43597e5ccefc8c8a954b488b5cff0bc54dca4b808ec70e5788abd83b9cc82873b1b3a7557d21c2d3251e285f09c8b5b75b9adde08036b4e278fd5ab53d30d3991b53da8184a839408ee7472ffc716841397f1b345067bcc9f7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfe774c39572ad4374508e77528daa9bd17226368f6520b258ccb4cba5da86445193a94868b24eaf7b1b5b3a3551fd815488d9fcb5fa4aa88078c1979595dc607	1631096177000000	1631700977000000	1694772977000000	1789380977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x04120535bebe1d532588b0e92b778d3dd9c96738c9c5c5e2da2b8d69049d60290fd09040d39bf3ec46ba762dd601c8dce07652f1e13e6ccae070edc6ac36f7ce	\\x00800003aa01517ed4b977d2a37c0a6d572f950a26888182cb2fc93386200b3c2dec22b234cda6d4ed000d2f0df6f6b368c403c9796377d161b2c345831930c42f1072eef3e5b5dae7890d17b4fd76a0b5abeaeee295d33d34afee8921f05ca0bd4ff8aa91faa619dea85060633a5ebbc83878d2a92426def579ee58a1e38179de0869b7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xdaecc0972e95d2779499e93efc7774151b0e37fb57abd21f1cb1ee529b26079763773f7cb145ff1c2d6add4aaf02ccc850d3992a8a72162a6fd34d2b8be6e900	1609938677000000	1610543477000000	1673615477000000	1768223477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x057a5ca030482d81200af79a2397c7ee8d27c8b3c119b04446345df395eea4ea6dc295ae907a40d070364441437c151800c594fbf747a341b362764fd2ec6995	\\x00800003bfa5c7d358cb83b8c97e6564d5780c8a3029b59165cad7b945ec23ef0617f71222a2519e5e28bf51d203c5c235c902a6bb87e601cb4084c4b2df55d196b783aa920e61d86195bf3af92f7cbfb73152187b7c12ab81229a055262e0de008996bdd4b367efd91b76cd8bd2fd9c55d9edf98f3ad9c9b830f5e25c3ff1b6242a8ffb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x665a2c82615ad1d0cf10f2439620280c61f753f1034251c611c6035bd39d5dce956f3aea6fc17cee5a1a5caa38d9f5226ec6b804e9725ba628b0572fbc8fb804	1610543177000000	1611147977000000	1674219977000000	1768827977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x06ae3d03872ee7a6792cb428b91e1058080ffc87da6bf4dd1815c0c2354c75ebfd931114562578dc7f9c6358cda67161378a9d49066b471593c6b0fe7810d30d	\\x00800003b0bea17aeea5fb9df168b351e379b4be38fafa834a383c9c87078a4eb31518eba39533708514c325b948e0d26d1340768037ec7b5939fa5f6b389e2a990225a11e94cb5c7910020f86cca7b160c7f3a58d5b94c2af60df9e39d8fc106d1ee02d974b4de10939161f2fabb32c10525c2640f906e64a54f8c762bdaa0c236fe5cd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2a5a0385904d34cc50fdfddd1ecfaf10d4bad896e835c55d20629f91ea8e7fe5d7ac12a90dd5ecff55d338436244ce8b982b33abff5c56d7ef8ce7a2fed5f309	1629282677000000	1629887477000000	1692959477000000	1787567477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0dbe3a1872fd94eb39d782eceaa9d67ec53e7634e413754dbbbd723a35af866b875bf722c3b35ae534d83718953494a719ffb54926db45624a79cc8575445a95	\\x00800003e50189c0bf83c1ed0a411a69fa2ab53d6be6464ae43a91b471937e81e2641a19328dd3a1e7f2519a5bda2fb138c795ad9ed3f3b796b8dc3cb359051c1908ad79525a7ac41b29dd35dfb009f2f82ba1b46b1fb8ee89fa8bb659243d2672ffa80c10e2a91c34d870126fa39778f10a3ba0bbd5862089360b0bdb41a91deaa6433d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x25c008eb3f3483853d1c51f74679f2b5f36513f93d264b2e4652492dd0b217c1e93bb545720a42707c4b103f951864607c4c05d47de51e532e11724e904a210e	1638954677000000	1639559477000000	1702631477000000	1797239477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e42bc5e88b9ce0af110fbdcb94c0745bf0fc019b9c3fcf7828bbd3953dd2914e7e8630cb2a610804e702a9e269563f4ad22dd933bcf6709cba1f566f2b1279d	\\x00800003df9ad65515975bf1ace9e17f35aa7fc12b3e92f377028dc133d13c5088964b5477453946609794e16a8687430074bcbbbff32065100be074fba4f68de145fd89666c7284fb492f5f0b37f71573d92aaf2bf2da72b0860bab7b807422c4b08df9f3ad8bb5b8f313dd46aade485cb6b9371e5ba1ebef686736d37d7c49c55b8dc5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x94f477bb6d75bf6dfaa68e9e1659f8bb7db77226fcecdf1e33c91b912a251fbba17652939045a160965b3e0feb1587838a6ee31a07471680ef1edcc193b3cc09	1629887177000000	1630491977000000	1693563977000000	1788171977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x12d677d1c12ae6c0c61684eeeb22403ea16fb7bd6f363cd066442a9cf6bb12d57725e9cd61e388c532b8d340acdcb8cd3896742ac5768a4ff83cd787e41993de	\\x00800003aba943d2eeca14290c93fbc647af738e5069c112e480b558744678b800881b027807a6a913fe826e0aa340fd00f29caf1c19ea5da9c917eb2cc46f040ef33acbf366f96ac3703255b7cd98290914a2b012289b8511cb50ed0579f898c1fca286e8aa131794e01d98420e5a5aca1472f0efc343f72726a771612ff882be1c79bd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6780b5ce22c8007c14c72ddebe1000e229fe67ce00f74e38739371d6e8ba418328e69ab22313f33826b85017de2ad2608be9de4cd2a004b68a2252fd93c68704	1611147677000000	1611752477000000	1674824477000000	1769432477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b7eae856b54b48610987d28bb52ee9d797b9e54f036a256241696ad75bacc76f647a5d87c6fe416bcddd311c264dae11068e04b29cbed2c52e249390b20ed83	\\x00800003de382fe3cc1b2541ff4ea86c7c6ee9523281a0b2381552bcb10b8a133514d7b53cfc58796ece6095643555f8c534d1a1826e530aeab3ba85bbc182aa1e202a63fe9bdd3688832434260c0685305b2d979b8a3bd1c4bbc02f40824bb20f831030d239bdeedc7086c56cac14249fd73dd766329fc062c24996fd637e971584a8bb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x017edecf0395a1195cc22004d34f9073d0d6dcdbfd21038864170e0102dd374ba9145a87452d84ebeb4d1734d41127895efb9f68d084d52a0f512536fac8ad04	1615983677000000	1616588477000000	1679660477000000	1774268477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1eda42d07b7e5cbea6a10e65ad805fc66af8ef35f24b1f8ef84f46cddb7b48a211d16f2eecf0deb18e43e3f1457f298896677a206054bafe36b5b14784588938	\\x00800003da141e25cb298f9f15822a0b5f000e23d9090979bd1c022617112379eecb3d56d03f67aa41de38b6af8dd7c786bbb0e574b7fc883b3bbd43e7d683aa9e5cbf27ab9b4a92ee6f2e72764718186323ce70b08c18b15e97575bb7404cfce3cdd573d34878d4fa461c4af93884ca74abd234e66d055cd86bc3f0e4bf6695b872fe5f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5009647c06533607e022a72229c7a3a1e6c5619dd7f0c9ad7e794af7b874029ba9873fd3322c9281308a98d42325b73de5c412350af18db711239d947d275404	1624446677000000	1625051477000000	1688123477000000	1782731477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x21628e30217ba99ce5bce2a6cdf0590637ceae74536569e34c99af2aa4ec802e97aecbc69e10f638663a5afafb5771f4614bcb88bcc5c48161a5c9a33533321d	\\x00800003e06e1ba6b10bc1c39c6256bc9ead5d36e586c4ece68045d1229b71fbbd42baec2c0f3d27bfdde561f33a65386698cadb6ae8595cb5edd5f59b95e01d09cca77a98e337a92035a2932c856892de7286fa6107a360dbe16c49d5998b1659c81a72e5442b7874f876b44898a78c8d56a8cbc27a0c1896c08169640bcb60573aa66f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbfba7f1c48863775e3d8c395b01927393bcbf6c441bd3e4713bbb140da7674ba2442759ba0e1f74560192b7240669e0c7ca901e2b43c8564d8ddbc9769551907	1608729677000000	1609334477000000	1672406477000000	1767014477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x242efcc76f2e6ef132f7eaa28495248469f1685685ea2536e254a54d76052ba1f1f0c95578c84701214aeeead145a1655a084beb63dba5b33f07e93bd914f263	\\x00800003b9c039c8fd66df047fa1be068ab437036f16d2422697c62837981ed879df8006e9acb6a76133ea1ed936f64c205d9d3080ba4866996a37b4a11e040603690c8d5261aa9e716e49119e66e52485cfeabcd3bf606206a16c94489015b403684404ea752b89b461c69786a28359fcccaf7665b131ad3acebc153960481d2f25ea89010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd81ea505ce3056a57edb96c12ebb87b9a8ffef6bd2896ec268da3695fcc8c2969d9808eb85edfaad333028799aab40daecae59e2ef9d79ba56b45c895cb59308	1619006177000000	1619610977000000	1682682977000000	1777290977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x278a74cdd1ec54ee7f5abc0e5a7d2e09293f69b942ef4f9254eadad0dc56a60f20902f157dcf7943f7864b3a623da370508c7b174b3f81dbc791ab1d385ce630	\\x00800003cb928b95b805927315b1f4203236df87b3cc04de2330684f4cdfd2fd3a067a2dfd365282c9f3c580b610fde18d28a4b378c535f789525439fea943aeaf9174b87f979ef61d7154788e7f1103cf07753b9d65801facffde9e0bae35d8d3d8d063f56d2eebc3252350cc70e3f6eaf49bf302fc732fb505073ec595b228952ca965010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfb7b3df76aa8d66e4383eebf044b53adaccb015a519cd160a75b18de8ecc5981e204f4fc16af80a8664046042b2de079ac4607533573fc0237dae474d0c74b05	1632909677000000	1633514477000000	1696586477000000	1791194477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x317a5270cff88fedb5d83571450dafd0163afeb81d55867573a0471346911e17876487e0d1dba1ee53c2958bc5566fb981a3b3394a142f5b984fae829b576500	\\x00800003b0602521a70c58012b8bf82a455a8ebc30dfc287a63fa6215d49f96d19639e850208f8770b2eb956b149d2fa85bf0ed060a0fb9be16788127f9c3d56cc108beb8080557e9f63bae77a54286eda28ad7afbc9fb942c0f987dbcba91f9c2296653d023d91b7e95597df6afe3ca38073515a929c0e1ced09c74bba4e6ced88caad7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5e48f92f431cdea52332429447ab79bda61656c35e0f18229c7f70752096443a4241ec4dcd9b5dafb08ac42edaf246788791a42de5da1ed7bc004d1a2550f00d	1618401677000000	1619006477000000	1682078477000000	1776686477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3282c43952c5327461516101f7f24959607f200a53b11bea78c0bdfdaa3ccd1d17eeeda17bb4b0d84bbe0603c4e319e7bcc56bee9f64e704c14fcf22af6654d8	\\x00800003a57fdf1748393392913339ab275b9978aefa89741ce9a5e6a471c1fb6b53a758ef0acef3e38f1c17e2aecc4a1b3cc943d524b872f849c7c5978ee1d7ba20d9ab4a93c5366842bda30e6f21d3018e121341273effb0bd26cceb1f67a7c79c7a2cdc905c99881cb4813c1a1f08f97bdfe0855a7725d50872d0ebcac95fefa4ea85010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x593872ada0d9460cc3a47909bfc53009dce07c5856902491a61671d6ba1ac8a285e95c5cb2d55a9999f04aea0e6cbb8947201227eec41873fa9bb041a524b803	1620215177000000	1620819977000000	1683891977000000	1778499977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x339e516a5a7e398905e101b0cd0b9a85d4f260934a97f78b6c2b1d73db772a74f78f96d4beeab83e9d35a0b495fd39f0852e05d97448afc9457a5398a6d4bf28	\\x00800003949b22a134296731f6e26496ebffddc5fbf219c66903d341e94ba72a52f873f9562b62584feb0e1cd4ce8e3f2fff2ad60e79c642a83aa8bbb3d165e6018d614170e26df257f149566b0c3c70d9a2acd6a7a6a144adc982cd7a7acd873f83a65c411c476df0d500087e60c74aba3caa523f1c3ce04cc24d3b7468ca566aca390d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x68161541d0959b1bfdd7e3b909f931103d372df588897425a96a5ca8bb88c023911abe7187ce7a177985ec574adc6d11409e8d750b4982fe66376aac4d1de30b	1629282677000000	1629887477000000	1692959477000000	1787567477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x353eec8346a2cc679bcecb1102567ca2abd7b0b328e8af498cac2863943d07d816e512265f929c8cf62afa6e14ac1ebcf8d380881496d20b8c0d13eebc600bb6	\\x00800003c9e428743c8ad5ccc8b0e21c688b338ea9836e738d3286e9382cade7e74cf2df6aee0a7768b8946c1174bbd6e76257c9b7e6c6a502c1feba93c0d00dcd0b7d3ad1dc4ada13e57fe9a20c3d3bef73766c004e6b12263c86c6aa7f550c55b9b16cfa717282c68bdfb3d4ff60732c34fdbc87b21075f9fcb417548bea9a39afe57f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2047efd4cbf8ab30dc912cc98de2b4c2d104490834be0f4c44ccd5fcc0307d69e3ba332fbd6d477183396c71fbe5277f46410a32fecc28771a74881d6d17150f	1628073677000000	1628678477000000	1691750477000000	1786358477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x365e39ee2e64fb492fec29fd8e2f6ab650cfd966b65cf1c85008a3a0c9d30ced81d60bc3c67c9fd6b109bc0eccdfc3e41be1c8aa6863926ab8649ee9b7f6c703	\\x00800003c4de88a56d5a8459acff662099bedf1752e43d0e685d0604331a3fda9aee4c3a9c3ed1f8adff3e033c1a729ba6fa43648ffbc480a924ff3a6215d2fdef038639164b0140e8ab145e2e873e5c1ccea96dc47233fc161eb721490a4def0c76443205d5d420fefad6dc755a120cf0f656ed4ecde150fde27c87dd3d62864381303d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xac4b38465b830c328f3bfec596e27d6ac9eb66b065f31a631b788c24c51aafd96116ce51e06fc4cfe60ce0da930e3c722b8e9c2addbee647fcb03d57c6fbad0a	1632305177000000	1632909977000000	1695981977000000	1790589977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3a229d20ecefe6f05ad1d34d76527fa3350835e4d69f4ad48ffc1971955b191d07c987ab57a2d9967fde8b6be6015763a2ebacb6d01627586c6f998be5648886	\\x008000039d8f869f185b618bbe60bb524a41a79b403fdc6cbb742ff046c8c2afe6ea3bef66b4c54f954062f5ae8b2450eab85495e8386c5d76f902d4a21cf969710e4d7570ecef6bddbb7698020ff7c6b5d607fffd963eab0caf738be704d9f5a9a7fffdebcc326220655f27ed0532df1cd29340c6a462dc6916ee290a01a206d1e6f463010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x342cde5f4e2fc68c62fb36b1d7c515510f1d81ce0e5d0730fcc459ab7547f45e3cc49ff3c47c0d677c153842dec0f6e34ec79a1e717acdcbfc9b7c9b6819250e	1629887177000000	1630491977000000	1693563977000000	1788171977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3baaf601f7373778474b863a8a71b8d4d3609bd91cad4f2dab6f6e106675fa7684df57cfbffb29bbd33b0cd8b3c17469ec9b2a1057c02d5503b7aecdf265a5ab	\\x00800003c8e79bc36c98d2bb7838687adc229c6fd485d95524bf5d1b31ee320f807794a81395b871c763c7fb2f8c917b0e18abfa977a7883a90c13f1b9a25215f5aa7260c8d3d1886cdc99af5fad7bc607f6362c102452a137c209f70e184144cf3a1541f87509f40ee6f3f6c89e9d2ca73ca95503a3aaa0ddd2de493be7d39308eddb0d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x401e33bb33d8342c5dbaa81fb3e707e79674637e2eeeda927eb2a3c7445f40974954a912fef2d6b6560fc7fda4528da22dee504a72004beb94ca4a50815de205	1634118677000000	1634723477000000	1697795477000000	1792403477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x419a1e8f41aa377c27d4cc4403ffbe54d4b7d6365bf487be94212793568538e759bdfb48c48c4d5b3ac1c73eb93be45e85106bb836f2f785b76cc87c13fbef9a	\\x00800003cc7267658505f8be024fb0d6d7333d3d455c04583e396de3dca551288ac5299f8f41297eacb94ab6df548a83a27e1aadbf655a5834dbd60c2ddc83b4cfdb2500e99083adb1bc9af5c3215c8d53e849221e262209c29fee2b7bb7fbc7233431c0c3edc27dc0493be6642a876dac0bbf5740c5055f83ca3e459f21ff27597a9329010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x09e3c50f045a3183989113e28479e7748270ec7dc54ff6bc3b33752c56e49a1b8211527d9b426ed114ce222549f38d3adf3b1607a207d245ecec5c7e40ce1408	1617797177000000	1618401977000000	1681473977000000	1776081977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x43ae3b41c69f0eedaacb100e582121eab0871c4480d23c4d4e3d06835316ddd49a19ae10ca9860733743cdd35a02498859d6c722f756102f5ac0c261181ed5d3	\\x00800003d1cd5cd8b3a624b68addb79101dc1746791144c59b4cf3fdb682089f38e828848d377d8c51d733061aa597110f0c0479d915f837570d0997bd8622a28f4ae120ee9caf4fa9bb1213b398f9af6880a09eeb1e4d685c8c038b638b41045c46dd0fe3275b370f2bd4e4e761860410aa5bc48cd7c0e80db895e62437e19d79c4ed19010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x213028a749d992d99a64a9adb197844c2fedd24b8bc19e53cb5d5e984cd7ed4fe083159ab6f693d41b97c44018d04aa131602356fe7b9945defa22177ad3830f	1619006177000000	1619610977000000	1682682977000000	1777290977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x43f687797535492a71a65b6f21bb18a446f262ddbb0109e2d2d7f5ea951f1c2a58284b110e483c1f5177a0a0e64da217149f52a941218951991064160fe00463	\\x00800003b639c148b08df30efa32f85665880eff9557c5c036e1427857e7297d2d48daf7ac03c2e8c18369a0df9d127dec147e9961fc920dca9e8e17c02ea1ac04f25e227995987969224497c2181ff151f8dd60fbc0d590adc669f8f3e8984136b7f513f46a1f150f2b2596a155c20121442aa280506f8e522be57d384eb30760962597010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x70d698cd90f938db25c3d395b848f847251b7976b83ff5697218f53dc1588f5af37d65fe8f3c38e4f8a7a7eedfcdcfe65a9e0e8988b8d52705d88c403814240c	1614774677000000	1615379477000000	1678451477000000	1773059477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4546492c591e2dc3531bc8bd58cd61ecd04b47187c7772d04b9f5b45acbe48ea9363543eba1cd9bc497e27e65c010d3003981a121d73484ffc7622737be7f7dc	\\x00800003cab08ebf2ec3588a0efc38df4d57447917bf5e628db99c3b1b0f8fdda34b91acd082a9293bb7cc76db224ac2d2dc0ea68ea585925cd1e604a48a4b203098c5ef6dcdcee754a3de88cd1b77e6eec1b713b5d7103cb86ed352016607d52941c3ea8273b6fecb32627f8dc84b0f50456e28faa567ecce61858b323f6d923a158d29010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9cc410acb366d6603bb818be0d707d3236112dba241194989eea8d6bcdf9ccbb03137dcdd582603b8c003a0f22f2dac900908cad9f721001e9a6b69f04282203	1634723177000000	1635327977000000	1698399977000000	1793007977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4be2aa569f93c2574315ca533cc217b17b7375fc60cb2f99d9d13db18a38f0f3aee1d929b1963bdb66dd5d6f01ff0471c60dc3367fb15e8981a53c87730db0d6	\\x00800003afe2b4a0d8e3b1c57a402da8bc29f423d16fc16eca4f9596bcf43646ff6b8f0411ae4befe104a8d79e2404f2cd597571a5d0e3453c5ebf28053227566a692da2ab3da742825b921ecdc5bc97347153013e7a653b7d5a846f7b9e7adaace09827dacc6d79f62dd77932c000898da685a880209f9891dc4a62e7f77d848973a08b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbe3b8cf0bc6b275f9e2bfca7d302694f33126378dc354f6ab94b28fc25fd07994fa6a20f77ae656f062eed356db279d60e84b5c86a14a0367ed311d0b184ec0a	1618401677000000	1619006477000000	1682078477000000	1776686477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4ba6708bdf97694a028282af83d02f88a32498c314f1b8dea76e305fcd4af29d60cfa302eb813be5f50f0aa75f152a953978aa2bcc54ac31243c54033e6fc30f	\\x00800003a2d7aa47dfd65cc1dff14cf8820fb8c453fca4bc1aceabb0c28fed31bf20c1580bf7f10a3f052c47c81def9aee6c71af63819b4ee4a3205e8006f8b114a05f4f3960cb04c9a6da448759d35678d36017bdce514f4ca179e6962bbc6824109fefaabddf477dea41873ba90021d8076cf6e8689eeb66ae711e338fc788b6bd0a01010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x57b44ee463e4c0a5773bd995626ff1083210881d366e74df1fe2287c0f1f1d1b476052c713dbe71a99df79034a12caf05c318742b11f154282a2238af6c0a80d	1609938677000000	1610543477000000	1673615477000000	1768223477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e2219a714ad4c2407cbe98caa9c8028bdc9d8a9ed4e13de28861a644bc76c3bc85707f4ae7903415bd8cac6a96e4a0459e56058c77c6d40b0a4a989d7218134	\\x00800003d697326b236f913f57a2786f26aa4c0b374cfe17c1af334a3d55f86c7226cb492c9a5d58371cc090e7b4ad607dc82f8ae6c3d24260e68cf2b1a278bcb563d787215993b3a9712f3eadc72f53c4c5f7a67adff3cab6c74ba807c0e47d75858ee9b8d15e9d537b756e28ab382d17da007b15cdd3aef51308c8bd1108c2ca1a7c09010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x40f4b7ffbb4f7a0df9a971cb9b94e6dd22ded6bf0c59cac35cf4949e49172fd3184cadb074a5978ec68341e39cdaae89c4fe01e8638123aa04d57f60526a6401	1639559177000000	1640163977000000	1703235977000000	1797843977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4fc6b05234e69760200a5b6effb8139ccf9732a9c1dc9470e2d7e852bf9fed5f2f40b08977f28dff6df3246de10f627c9ac356c7f386d71f05bcb6a33eae5e37	\\x00800003c44752ff30155a196ee43a9530afde94e901ff2b3a792b0f8f903e0d6186333d0579273dc956958c271bac7cc34f145e5732b179b538c55ff8260d48943a39ec62f873005e5c3d23980ca10e9b6c25dfe38e6ceb80c8f368a7612c6c70e320be8c42ae536ec3b610c627141160b560c95c7176afdbdca3454b11ddd5347e29d7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd0450a4b271ea44049b1851d45831f7562ac12a51d4b1d7118ad6ce44e2d73f099fab4e2632157c5c6cdbdb09b9a1d9da584b20809b7bc52c73eab076dd6b604	1617797177000000	1618401977000000	1681473977000000	1776081977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x52de0ed0014ebde67e151464d0e0dd45ed2f06af5d1ea0512fbbf43f49cb321d6978952289328528942a85110eb821cb467445a5e7408bbac903f540600c886d	\\x00800003ad359d6e2e3511e9ce9fbd5439a7191ddc8e946600676e89a46243b10a858a4aa5916f214c3a3a6414f6d7a2c10e04b895b3b7c5fafce406152181b678af20945fd850095b23f57598a9e3eac1d696440bc8ec78cbaea066b763522c4cf43d0a8527d2dd2b25688e71dddf51eac22000f93eba27ef6bf58cc3474b009496400f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfe00628a7e0eedb5bbe7c8d87bceb16fcd9c380fac2ff009e6494d772eca5c3e903a76df4044ba610593f91de7d0393f0f2a82fdaca7845e26ae393a2ac3a502	1629282677000000	1629887477000000	1692959477000000	1787567477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x530626d907f2a4ff540fba646210c4945ebb4b6d1b613b70fc65760e5ca29fae6844be1cd99f078f9b69e3fa6b22afbfba21ae4121dde65c35a7a7f5e8368e75	\\x00800003e2e29510b809b903ae9d64a14bec52f112f5b1d4cc6873e434c5e282e28ed558688e0e3671e96c3e4f231e57673ea82cc57f2924f6985aca7855b690b45c35772d1c420b356914cbc36bee1830ea0c1484cab23090f9bdbf80f0504b0d0a4b1dd357a175d0f8a94e96fed1d14d23831b10e059c856db4810714dbf6e2baf25d3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3150310b8c0870f082f62c49eaa466966ac026603fc16067387469487f96740562dff4afdffeaf1f3b8ca2dd89136a006876f1fd96c670a84af3df872a995205	1635932177000000	1636536977000000	1699608977000000	1794216977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x553236512bd78ce076177e441dc8dd5ee3c6ab6ee07f0384ff5aa2cfce5d1be45822ab9f44a55cc5f91fcec19a94043bced52e0b43ad82dd6d83422fa31f2d12	\\x00800003ad5aecaf6eaeb5569efc2f2742caf76920473bc84acfea64e1bcb42d2f38e438b125b154958e269f7047cdb70383ec1d7b4db59168093ffef5bc6ae195fe746abb43721f4f1c9fc8096ba21c72df27f3ef4e5da3a7da0c251680b016eab91367cdf2936ff3f4db063b5deab2377b51967d550d7e05022f52e6a609b82810874d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6c54a214752256e4e9b5a98f3f3d523be3baac22c563dd848585948a23aa3d1ca0a4c8517658309aaec51c1dbe55d2089a57d6e94d9703713f89e0394a69b305	1613565677000000	1614170477000000	1677242477000000	1771850477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x57d6121f0c97337591c481351bb50dfc7ef40974ca88f60c17909e46b643cc870c692242c29e9030e1147de6792071570427c0cff431f112d5ff4a42eeeaf4a9	\\x00800003bb6f8fea64d42bbd9c85f7246f2352f9fd0234c71a70dc614e9387a3369e8def79967f60d1dc66064cdd6dd3d98f53c504d652c242c37733933587d50d5af5f7849236491bcab8385afef791b47fd51e67af11ccb0bd6d31ab2179c053f46b97fe8851eadecf334d235c58f0537ce545ec78b1f7e829afa2bdb85dfc0a7fb6dd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x48c63b8293c5cd4171dcaa5e34cd37d2bdf02a3e632dcd44ca4a340b5bbdf46e708a2e3a9c9570c0e4fd8f61e3996dfd7307c649485dbea074554bb389f75202	1629887177000000	1630491977000000	1693563977000000	1788171977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x00800003b077af3be2b45274aaf177c0f057d1f7dd0b87b7ffe008a5a144848cf4192c37b421270fcbcd98e6a799ad770981220a3894e437cd73817fe02d339760385c1eb163cf509385d97d9e7c8eeb20d7efcf0f520766279ca8aabc62dd15e481d636801c9dda09c235d7e4aed5e6d6e8aa0b80031058ceafb9d8dc977449df4eaee7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xdc5252499837eb97ac3a8632e0f8a785d40644cb23c3d9072f35d79f5dda5ca2f8bac5893af70d64e61612d70648b0b36f5489a8d3f191936dab7762a0ba9e0e	1608125177000000	1608729977000000	1671801977000000	1766409977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a326a4b6db842ca663af42c5a3340771ac022363fedc665c23e2c5537df5857f9f35c0669c569a579f83735368043e1d5f1ab06b90db4e3111dcc36d3c505d5	\\x00800003bf19e6a2d92c1fc3193ab600f20904bd60856c5815f3323a02755ba5e84025b499b3d604df617ca28da74ef61f898d52e7e9bff0f11704a772591c928a49411e0ca392463b361f0abba5bcf60d7e002fde186b0c7125820cd6bbb132b9eed0807c11b42eb8304bff7c6e09a5ddce2b56785f0605d6f86a3decdcb88033195297010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd29a69a1e5d3750bf83b4c392c1e3ab4e840d58bd9c5be1c72635db2dd75b7435bb0a4fc3fd662cc6260949f5224b454aa9acd61e87d02da635bedb6d50d1306	1620215177000000	1620819977000000	1683891977000000	1778499977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5c56ebab1ac4ecdb57610fca05c7dea89a6783bb2f8e86a402b6ada0c972107aa68c89c0e65cea0de34b22c698969250129125b13201f7f06057e3c28a9b2c2f	\\x00800003bfc7a8ec8a45e55e09d0e0b0bbc48f1349aba54961b0ea7f34b2ff78a8100dae2ac1949c9c82b7d46fafda81387c4e9325fdbdb39178f957a61e1ba0fa033159b574e156b4eaf7e8598a37fa46431f857d8d18bdf2a45b4e80e8e60a81424d19a0abf8bc8c5dec5e55cbdfe83f7a34ae0c9dbe3fac8b73d52b10a5e01c5d7fdb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfc059f2af5ee3ed94a5c075896571c2f5c755ff5193cb37f1cfdbd371514d915496ec14d432ed15ba90a9c46b9bdd5ebbdf9d12693dd32f92a7daf5a5a67260c	1638350177000000	1638954977000000	1702026977000000	1796634977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5fce3b2a51e681ea1b38ca9281bc5353c17921b6be0b65bd312170740a7b12d9c56dd24cd280ff3be2c138ac5eb9146e55211f71f4d2443036f43c022857c571	\\x00800003c0136df3c0fdddc6463462673c7f3aef6b9a484fb5f0fee000b41f0885ebd350f69b76ff52b2dd574fe9c0829721fa1454c42bc57f175ddeebe26a658ef501c02fb1e4d7998925dabe4dba4f9b20a18fe3d8162351ace17ae327fc4b52b938d25c81541f4f07bdc6149c5502afee877d3c143a7810c83ab2f9906e55196f428d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1cce627b2ece09779a2fe5b687064425993005bb773a236f4d60761edc2f9c7152e59dd0da80073777131b737c091d10d82f963da68ec2ff15039189134f2c05	1630491677000000	1631096477000000	1694168477000000	1788776477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x609ee0b7f997b745344317c1d100028e594a5c3793c3466059593874e113d4c4a52145d146802e2d2849a4a5385587ed124b8a4e9dd0fab75b2e092709c76e39	\\x00800003dbc2409e75919c19715c9395faf3d81b845a411b56cb8614ab2710c0c9c2bcd5365bb42ab5d98396ad44816ac7f6fe7af4359e1d2787d92eab20d8b7352a59bc16b445c8a4407be21e1ccd6816abed60a646a90a8b5a2bf614f5883d937fab54eee619de07f4c138a5cf0726a66adc3334f98208d54e0baf12c22e3ab5140313010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe435db12002951098456bd2e861905f4366172ed3da2effbbe5d034615ed82cba225b591b138a6b8f4bef121f8d1a38bb95cf87066865bd446a6776a4f359608	1629887177000000	1630491977000000	1693563977000000	1788171977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x620eee385cf936f93c7f49f557cc693b1b0e8663d8f5e6b88f4cd4b9245fc7a031b0a578c52f4815044e0bdcbc2f52c9c563ff4a5d72e4cdde7b3a2822954f0d	\\x008000039e830aeeb540be82dad0e5673c7bcebe09ab960b604bf1aaeb6b4559772eeebaf61a5c97a52cb720f29e0d61ee0de978f014d6ed2dfab23428ce2c552c5127e35507a17f95648b4d19441274c2ae245e00617fa494fb097b225e012c49fd7560e5c4505c5200d369f629cd38473d0201d267238f75e9ed97bf63057640428fc1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x46292f8cd2e82ce8ecaef43c612590238731781c1278a9fca54042ab4360a1158bdec60f6ac01d7ec7e62ae9f75aa2869764f45ccd428654d6580e8f1ab02a07	1619610677000000	1620215477000000	1683287477000000	1777895477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x657ac2f94d4ec4f58d5a1d700bc7d9030156b40e49b210f02430e69fb48da6f6add7f5c7e0d514b48889e6e1059e5aafede68865cceab29a05e09e7720669f0a	\\x008000039f320b72097827a04832df5467e2a81faf05ac8a7406132321dd9042aeae42e4ab7b936ea0c81c0f75fbd8702f00217fe493a9e961c70c3a035df0e34e1be66df30eb1a4decb0314ed8f0d9c02845b30f3035027ff9bd8f6787db67b34b96c2884060d4a255ffa5094fc68c1ea9054505008089b7ce25a27814c2eb34844fe05010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x08cbcf1004bc910cc34b363ec52a8faccfc66a4440aa0855840b0dcd3b8b2145fcbf825f899c0ea90f00fa6ea54cf3ce7fc7e54dcf65f63ea1f05cda625b6c01	1626260177000000	1626864977000000	1689936977000000	1784544977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x651abd80c5d1b53c99b45d5edafe91b0986e336c4957c7f2e9d0d773395973ab504b71f41ee4a968773202326f6b1535ba47bd3020da835c739d4dcc039e43f8	\\x00800003eb922dd6759871c9cbe7869536de21a96da50c43f6723200c3f36975f5f06066ca1eb137d0a4fd1e6c1ae0ad8111ab443cb7e9ac530e686949e083009e4a6519028ff98967f56d4bf196f87a0079e75b9053ff1db535657e618468c9ceee4263e55c9da4a67e212ff3772857ba9cc0ffa258ed4b2a1733fcb6338aee61ac6b6d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc90f2b94cd2a9f4bb4a14ec8ce090c50c2e4a33e7129c80c17161a0ae6801053e06051678c38bc7568564306c96d78fe137211cd5dbb112a20c71eef29abc703	1609334177000000	1609938977000000	1673010977000000	1767618977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x665e62a3aaf309ed274007286c3756c9b390841cd3ada8a2dd1d1d2a981b971de485038f15753cab0bd95061c0ba6855f2a357ab7d99b07cc871cee9e1aca0f5	\\x0080000393b7c2ccf8e24ed6857e425c61ee4718ac4c69d219ead64d5e5a5957742f27483ec301338d2dc46aa1b673b5de34677074777755ababd46bc32ca41a16df202c2b6065e6250914fc56e2b3edaab31e3ea978bdbcb6ebf5c422435d798b6c50e5d2cae40893541135b1bfef92b31a5c82e05582ba1097fbaa82e3962bf9688051010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa955e16ba0b135dbea553f1929bdefa26a23fc1a0f1933b17027abb96f7e164141b5d9ce4c1d5675e4ee15be19d9f08a0d6953a2d0c4db07fc600e780dcf9a0f	1622633177000000	1623237977000000	1686309977000000	1780917977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6636e99702c8bc7393804cd82624bb1e80b5ddb52eab3f40656c1b115693143064df78ff42ee019c9fa1c73d6462357e763eeb8208d98c1e0ec7841c0059aed8	\\x00800003b6a83ae14bbeb8fbdf64aef2ded641374676448a439aed2b4b649d2abfefd89eae6c9a7236c2bdd7bf126f22a2d67f42793d16df8ec977db6416744046f8afcfe53040ce0c5bc641ae9129900f9b9c275c40d4851cf0ab5ac79581f9a6d7277ad9a3102fea283929fe21b714de8df8029517df581a34e525d6b50ffdebaa4a19010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb7adeb0ae1d35e0ad1da466e57399472672d5150f3199c51dc4a0877e4543f860ad0beee3f4d97db84822a4e58667459424eb84e622aabbfc83ebe9dcb506403	1619610677000000	1620215477000000	1683287477000000	1777895477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6a82df9047f6aad9923220c87f0d5a0b6d84397800bee0475eed7b1ccb65294d16968960a92d6e9d131b7f4028e7a7751d3062a0fdf5ad8a35504645bf4afc88	\\x00800003bd7cc18eb3c4a4ce39242987cb4ab8a76e15bb9438beb9cbd0c39666fd73eff060659384e901c39d83211ae2461a6aa6a4c51c0a1f2689b8dc169bd8a84ae24bc15277ae5f4fb28fa0807cb4853b1f2189e12ca4a7c3a6a50d53e94ce7ae38c1e322af970dddd367a5684e3623e50b6258e8893974c3fda655d8da7eabd0d6d9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x91d44f759f6dc84ea4f0c4963697a013c8c86998d3804d7d0bcaa3ea31f04ae513de2e2a085ae00bdda84e58b06372c0bd3ecc2adfbc9d181832370d353ec207	1608729677000000	1609334477000000	1672406477000000	1767014477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71fa83629571ca092edac3aaa84042116dcba1e1a4f4b172dbe37089891f49d1037fb84a98a85afaaa75edb24526425db10a9b13824cc7f2cf305044924014e5	\\x00800003bc44b5019b969e9042e7f7420ab6277ff8877112b57ea388bc072d8dbb225195f2b350c8d7dc9f937ef349ed8c07d27dafd587d998830f8553c52c8f643fc6645b2539e3c0c7b4c38e7102a98d6ad0a38d2c50beb89e70edc21c25f7fcd5620bdbce1b622b314ce1b9f660a7523cf74bac1bc966e15805be7c42b2e539f5f60f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7a8c4dd24f477810f0dce34eb7afe7e5124822e2848b100963511649fa3aefd164204b2dd68a3825ef920cfe791f305a617b8a56084909b00525094f7e1d1c0f	1614774677000000	1615379477000000	1678451477000000	1773059477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x745a0d281d20654e7fd2c53624d7ef905e45726ca72977889a73b8a4067127a43f128ad68406fc27955237cec1ad828e149ab569dafe16fef801d868daee48fd	\\x00800003b2004dd1fe197639c63a7596197a3bad5859ec33bb56c51046996faa7d60034b14000d9345e3975efd0a3405f845ddeb812a7a73df1f0e7d17afc46adfce57a8ab5280080f1989ecffac6b9e9b5b87ce8b1614aae561848c0aa3a932a1114262b0cad6388451f4867f1cb328f222e0d01c135cc35b121b75cccedbc4a8804f21010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb9125be27729dedec667507d3e9bd4214b0cc24d7f0d0b297f4f963d13e5f735cc91f5df18d8c2b240028de31040d69e8dce7106d42fbca669115bcffe317f02	1631096177000000	1631700977000000	1694772977000000	1789380977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x754a4e8afd048273ab1b4b9d76dbd8c3e2d1209b806dc1c8fa0d2260a0f446d4ee980444889f94fba149e91b20129ffe4b66da1d0aaf69292d7e35fbbcd2433f	\\x00800003c99a28c497df5c552a7304720ed1b582bf4de5d4cd58ecba8d2d9ef43ad825a2ea1414da884fa911cf084c4181ecf314847d808558edf4e8132e53887986493346987fc943a2b3ac83ee478a305abe585d210847d07be90fcb89b116fc87ca23bcee41f2cb4a7527ab8a980e1ce606bb913f5ec830b59ece86a124676883f207010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3e6a0bfc8bbb553436b964a946ae7ff51e96dfa43c493d43310b93bc1d1a183a7908b3733fa944df612d49dac9a403725d9f33392b04cc4ff8f68d603403160e	1615983677000000	1616588477000000	1679660477000000	1774268477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x75eeb9db59e87ac1273bbe66670d642e7acf774be1f1a6afc76f4feaceaf030044f2c0e95de434987a03d0da57eb885485adb0a2872f950fce9243e6ca64abd3	\\x00800003bf633cb756da26fd16392b720d055c69c7b0ef7b29bd0d20e15ee52090280e6a55e8106f4bcaf353eb94540c901077490591a04a0b9ec6e228517ff958b4571659ee2a9e12d4f9aea9e474be1056f7b8e2f3dc70114297b9b3bd1edc5bd51c56702155899c129a5f50f45da49d4050969e578de0de7b431db64869aae4d4a369010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe8fd9dca6d2f11d93a307172510403b54a3fb54afb05a8dfaf6ae1b01e97a04ea793f0cee1cade1eb772feb903c989f492a1a1bda2cd8f5fe7d8a2d15d14060c	1639559177000000	1640163977000000	1703235977000000	1797843977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x79deb31c3ad01c6b9ebeabcbd0cef9e3e20c9ef749d992c772e876ca19b2dceb32c52064a6f83c070f002eaefdb9a7dc5838b03a0cb985177b638cfceaf9cdcc	\\x00800003c8ea3b7ba29873db73bfcadcf593c6dbdccacb4bcd4b4b70f38c4bc3d383e67d1681e7d97a248babc77abb0453aff028c1acf60e4443537eaf0d0d00e10870d9ef183367f25131ca3a7eb995632185eba2a409eece001744d71819cc9307b3df30ed057c100dc1235e5ee47faae837c0313856f6bdfab64b56b1244d0f04b351010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x034a2a29399cefae85db399fcf81e72348c5ff79cd00f14bbf6ba7eb4d60afafc84619cc388dd36a08c0255152fc175d63400524a45b884a01b8f466f4261809	1618401677000000	1619006477000000	1682078477000000	1776686477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7f8a87560b8b69acdf6b1b09933dc5dd2572996799bd072ac9d9ba5d2ca0ce93894bed48196c1d24e394d6a12d1dcddf458a995ffb3c25042c4b413a5511423d	\\x00800003c1614398c718426a98d0c016c78948ea04d6be47811302b5c5723989efd63fdf703a50ad91d85546e9df53811160f681b03d547b825c7fa25a8e0e30ea71a577945a8b44693cdb989758d26f89826f2f2313faf4c7b895f7d92ee36972b52e81dfd01e6b5f62c3b2f9de760681e8f0d0e597f6888a23dfee1f690453d48ef17f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa48d3c73ef8d49741479274c87a936b42a8844767cd3f4f67c1ee9ea3fd767f448a732bfb0ded4515ddb9aaaf74560cfafe8a70f396c87c096fbbe0e733c670f	1625655677000000	1626260477000000	1689332477000000	1783940477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x80920fae02caf5e2c6e2cb9fd51f3d020650e33ce8b83a9ae6bb1d8eea73e81cfe15067a1bf72ee9fa5be96db689961530641302247a70faa285b7dbb5c1d7be	\\x00800003c72faa225734b2048ff540be3c7e127230fe48cd2ccb9fddc62fe31306b8edc701c3234bb41aabc913ff98756fb626f1f79512c85f387597fa59e0090e2c840073b9ca5ee4ab51d17931694c0e45f285f1058d444ce1381f22389cb993e6f9e544320d71300bb8b0c7a4f707779a30da5ce001550ffc636cc6f1c964e33e0fa3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe0b3bd601aceb65800adff0e794172aa8495d1534f8669d6090e00bc3f6d604840748835985e339e3d580cd635a17726e4207b014a9bb48ab89559ef388b9d07	1624446677000000	1625051477000000	1688123477000000	1782731477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8a621d714e73b0f026e26f42123ce06557bfa162f479b8c7de57ffba32f6e8dff669b066b48b7aae793e961b0b7341ed1fb43959633b198ce522dbf2ba3949f2	\\x00800003c44798a4b66818fe9f6ac285383305a914d2e8f16f23a2b8c8af269e1dbca6b7e318b2221eb1f844e77da8c265ef891af151b9f089f71ef3c21ca9142e6ff2abd4f635e9deb758c8359d7fc6026d194ba5295a77d7c9d3d8209f691db549c0d03dbe74825adca9e727e96f6411a21dc0a2a0146f835372fc2c32bae14f2e31fb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x10072383ad1bd95bf207fc9256f01ebfa68db74eb09a30f8bb1f99cf7ddb559426479258df4804656c49311756c6f100ef9e192572312fd414e57cecceaab30e	1637141177000000	1637745977000000	1700817977000000	1795425977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bf66cc4b40c7530685347cf4de73f4c38fdec05a50a2da0ff1d66c6be685b3545c4c6fad8b9d5eb5fb3867373aa32864a4a6c10895ac9743504e217ee36aea3	\\x008000039eabe00e891f78e0387cff77ae5c6d62e37a780f851688dbb23b1b85a66a3532524fcb1723dd414f034a66139b2d91e4b9fb512ea05fe6b0bfc12e31d28f54c013454b115e6d819f6abd7fcd55ab1f1a4f66b205ab229de647e5a72b2f557f199343ddfdad37079090de1689fe5e97e99b0439cbb4d2324858aa5e3a3a07de97010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1de3da3a06728ee941bee9e56169161759b923e4f815b8ba6c84fd6e5721137449c8e0ea39a9a6a25e4795229e3a07051db19090e3df43a85b94f04a59e0d706	1638350177000000	1638954977000000	1702026977000000	1796634977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8c56e0bcf8699f28324b658919ba06f123d83d9f890d9d2f34d5c990f7924a28bd0caffaa6151984764d15a12f2168dd032e0cfbbab8e1d6685438d64952a979	\\x00800003bfe26d470d58aa2f79f65d5f18eb4cc5293ed4e5ef08c715dd8690568e8c38d192403dd78e3f12a1c3cea8416bdf415ba44f15ba8c0690082b824db9af8f100201a99adc3771d13e071a9fcd07aa9c115752ceee1878f7dd967bc8342b0c3bb443c1fec91a4f69fe841d5c1acc4f79c9ab3fc8cd24b5ad8709329b8a62f8a257010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xaf3dd79813ea8548e42f691e56e35628f3a56e7e55ef091befc775868817a5a67ea19b4bc46a597db9f8c6d587d5e99329a0cbc5b789615b0544302ed8c68303	1619006177000000	1619610977000000	1682682977000000	1777290977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d5261126adaa5cccc41037ebefe8c753f91ff8bb395fb21bcdea57c0b2dab9ebef3f4feec0125623f277b77322ecf30425ebcd5366d1a1256e794f8205073ec	\\x00800003d0bb91bc3587ea24fdd79a583edb4b7b0aab928f422978b61346b55bc0d7791be16b5b715dfd9daf9ba9c2dd261aaf14ddea4550a760b211a66d729b20123aaecb325d113af4f6aa8ef7cd2d10b5ca98af255ae6a5acb47d2229e45926116b287b74b2e1414d2a650d09a92cce5a6306843bec4133a3bf26ff75fb40b9268c63010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x01f59bad8ccd4574f49da530200bc4e75ead7a1733636345795d3b2f53995792d9c9416e628f251b1b7f2b057a10046069b7bd85720163c97e4c0b55d54a1c06	1609938677000000	1610543477000000	1673615477000000	1768223477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x90f2cf116cfe98bb7d89d52de500821ed4a72dc1f9fbc4f5a112dfada8e486d4159eb4bd98f881fc56ae25e1e1ba6288adf112735257a5bd3d7cfe26c03a51ba	\\x00800003b4bdc91bc97e264b5a74949c0cf7101dd9160d0fe7ea122bb3aea3ec74cd2e6c8eba041faa7ec59252395188dc1bd579d66000ccc61e26363bdc206765d8141cc971064ee313fdfc8b7b8323b86730c5d5edb6a4bf35d8f933cf3365c05702e538b4b56aff7cf5b814d87647550c24cb1caa5007098a4d64971549204bdf6483010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xec61f6e0f1b704ce8c07689c995794ad08813509e191dba8b91c0e2cb06cf5e2145474bb4073eaf8ccaf2db0f5876feeff719bcdd6634ce62fa36917c898520a	1637141177000000	1637745977000000	1700817977000000	1795425977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x91ba4253ec57785b5855723d836dc53bb69354dbcade4babdafc1e26f7999939c240b0adb684d23f15266fe31c438d1660aa1dde359482cf00ced7ab2abcd7a5	\\x00800003c031284e8e6bf2d479c0fa7ac406d7c8ca9153e9204bdfcbe6c4950f902e272ad3ed206fbae81a48cc85e57f8e2b5adc805bebdef05248be2b95205b8044f79c5e42f85278b3c6daeb2ecf6f247a1107c85ebeab0eada3b252c05afcbe74720a492959b5bc06e94b29d931729d94d9ff4617de43395b9d48648b6b708c0d812d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xcaf9e0dfb0b0014dc768a5b7f525f00e64c790716d65a17603cfe516036c1aad7589fa18df3d62fc2f13abca4aecdc3e7b6a659495aebda24e511d6c74c17201	1617192677000000	1617797477000000	1680869477000000	1775477477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x92e6cdf4fd959b757b8b663d2fb0b63927b28d5da1f6657d4041e4e01e6c2f9ec66f8e9defe43412a9af4a08643f7916646fcf8247834290fe160d02c49b4e5d	\\x00800003c7b625a4d5961775f29293993c456663c2f99c4832301495731e3241d31d2ba861ad05ed76497d77cfc472b3362cf49c321637aec43a5aae77c1dd1b658fa277f307604ccd68660062c7eb98d01aa503f068bd3c096da8642100fa5e986cb00bdc5b7e1a86ef63dee488dae5d7116aaafe579b9e2efc3a7af61d2f00e8e59e9b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2cdd80735b0c3da411a2e089184347ddbb09df112e7c3b444362f964574d8b2fec980e9b923e0088fbcfb38c5741c21ac418f5449bf2a25096f15fa0c0e78400	1617797177000000	1618401977000000	1681473977000000	1776081977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9502c72efd71133b8aad0c8193adac2f23bd070e775af60990574f2368426afac209123bf7d68984e9a4aa41c1c57c71d924f618ae72fcfe1869fd8b233bba2e	\\x00800003e0863eb1932419012c3034622bbaba3136ab151809b78fd23633c5eb32917c77b68e53422e13b39f8cf0d37ec75bf7c74db88830838903c54d7d8b079c01906c8399a63dd340e2730f897d1c4effbc6a092aaa46f349614611b47ce343dd60de7eada6f4162e83cf9e6d62b1b14ffe351d6aac0492ad234caf257fad963e0077010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6e8c2ec8f2a4707eb481c8c36759c97421866b14fe57b04797eadce25effeab63b1023be200cccc03f2ccb4b708d8925670e3feee30ecceb2c05fa82412a7201	1635932177000000	1636536977000000	1699608977000000	1794216977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9552908c94aa815168bf1a1ef8cba117bfcc72e6adcc4d9548279430a67c689e2a3ca65522a730282a1a4a2e75e407b69621f331066c32ba3574573049d5a174	\\x00800003def2f4b27e3cf3f5b7dfe5cc3cf6f80ecfe1113538355ceeb5d0ba05a512447b48665f80881c827eda89746ce6f033ddea3e2e9920d740c70f03d44b9ae4c0fdd9626969421f91d25052591db3a988ffec325ab33db7226052497091271d472c200a1dd4e43f38a583a940776a59e28cc75841c8ee919bb116041bff77bb22c3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xacb580e3e602a107b95ec77855802019dee2b94b0444bdc21b217d48cf5f7d5c20a85e95b60ce32e5dca1f4cb107ea78bdbb2105aaba3dcdfb1b76342c2fd409	1621424177000000	1622028977000000	1685100977000000	1779708977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a2e98007c1c84ec38693e4d69eac290d19ae8d0642e7c35b910d926d17cf643ebb3beab924e1c95dab236bb82c0f8b0558a39c6f0703ecb1bf755a169e5a62b	\\x00800003a3697c82ade78658cb15acc717e2564ef05b889715b9f0bd96390e085f361574a3c668baa983305b5ab3b2f961879462b1b4a4c77c6174358ce19698281819ef2156d5cfaab6008e12a4c0c64aa85e5a6ed93621e45613273331d3261a4b087e7ae5899cbdf878e20e27cc050868c76ee3a64a819ba24ea4cd4b285cc414f519010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3befdb1f4b4ef09ee3f2a6f60f2ead3d4aa71eb387d09343a9a1073cbf89ca24c223f902c7f73fcb007bd6dcaddec570f56d14f91ce9b79e4b30d1d138162605	1608729677000000	1609334477000000	1672406477000000	1767014477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9fcabd59c89444982f7f6c1c9cebc3c842fc2bd60a354d4be8b2fa95a2eec5bac1c03f1437c540ab958aa625662b434fc3828ea27665ab2613545ab53e6d5cd1	\\x00800003cb11aef0784724d16032c4081197eb338e8d7b0e9a16ca47c399332cebe3521e0b0ca6918be46d7ca15440c8fe2abc36cc748c9768c9ae56aaca230d535a99965ce46e771afcc1cb61bdd4c05160fc271b57388ba9b1ac006ad75694fef3ec31c1b0e43b471a8a580b5424ad6b3f87d2754b60604f22cdaac4a355dcce67b32b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd0da4308c7c8d9d28e9ab76e84692466ca0694f471def8f236206e0dcc53eb83e23f5e417adb88f5aac9359fbfdca905f89569fa2bc9473ec1f7bdc333a8d202	1636536677000000	1637141477000000	1700213477000000	1794821477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa26ee08bc413adad94cc7bb3daef090d68dcf524867726ecfe53ec60326fad1da2afaa0375e781794cc3bca458e47356498856253e71c704b26fa9bce17d40f9	\\x0080000393c2ebdda66c889cdb9d195a8db05f1dc793eb243181bec6867d992fb7662880997b263909f48e36940ceb7260553fcde447578966ff29629996d361990b74b4b126cc0e53ceb10808aa0e6cbe7cdaf2270a8a6ad2b4c0e1b8f03602a244562de114c167211d1bdf4a1ab8041bab7616203ec4e4fd62f4e2b74d425b228f0181010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x18c88c0d338253b59a35cb6f296c7bdc110d9214ba1f658d2841971203ecf6633d6543cee1a4efe6fb4dd388e8b25e717e08129d86cd8189ead11506a29cfe00	1619610677000000	1620215477000000	1683287477000000	1777895477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa46e82339bcaf936c036bf7ad96bf15d258a80bc47af60686b37fe2c15ae71389cf18304868cb5a876568c93564b2c1216ce63d773ac85df01acfe5a241b1ec7	\\x008000039c88af02af9477c5ec9a3cce5447f40420e8e1eb439d034441fdaac7481ffc39c21265095c53802f087fac3772c7e14d7686297a202492c756489ad121d6a085ffe5ee2865b9f174516bb614c1312dadc9faeb5c6e9957f961460aae13fa65e7bd12412b812c32722d3c0d19cec457ae82376ced4045b7b9ce86593ef9b3c8f1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9b06f53764e6c0da94d8b1b1cd87976ca35d71bb19026355ed7334ec36225544184bdf64ff08fc0e2419b279f21d55f749bc7e5d75e7fd5c2dc1fee77a4b450c	1638350177000000	1638954977000000	1702026977000000	1796634977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xab167044f012437940b009fad97bd4434cd09178a290486cdbfdc33b5313fafa01a847dbcf58d111c795bf70bf4061c49ba87bb36248e656a8ba31ee281774bc	\\x00800003c1814131e0981d42b0256ad71eda717dd120eb6daa32e46f7b84bc377d3bc860cac87d4003c543513a31a00f1c622d53c15c84be492d938ebf436ea437526d8f857fb4845a12e6cbe8582efdd0060a4a64d827b0da505451ac5d8c70cf571c6543f6c0a952e58b864feb607fe7b4c211384414bed8922d6af57a2bc569cb49fd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x906ab44bdc5092b06f5b0c23065b7a2eaef5e644a8691ef5800f809e22b7bd0d97526a94371810c6795eba4b92a69d05c8cf7fbe14533a8e33b326aa6e3b220b	1617192677000000	1617797477000000	1680869477000000	1775477477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabb269983c12811c4b6331b9b98936f2b96e5cc06812904c4a96b13808217272babf424b693ef54f1ffa86405d2e9bd0cb771a087e7abf1bf1cac46a715a6156	\\x00800003f38e33ee7767d0f10371fb765b44843abdb86df26c7948a3b8044194c3f2320b2e832c9058e0acc66c3b672df32b06840d286f4a6fd08b8ca6231eb90487b9898e62122f1619cb16c1baf2670430bfec22c5c16a3c5bd220daba66f6663de3a880bfb51bdfaffa4058b1d1164c7e9887ce2efa057f9c02207175ad7b76666c11010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc888117bfc30db5f4a3ca74b91b0287ff6fe046175d91ef78a050b9dac6bcbe14ff6b4a0fe80679851758255c99b1840577848365fe37322f077e65fd24d2604	1623842177000000	1624446977000000	1687518977000000	1782126977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf226c5b1eae0d42a7856e9483abf30cf0d46fd3408f3b7c794d47072eb97eacf4eb010c6ecb1237b367026587570ee2cd908d2f255c3c0f2520817e7deb2fb3	\\x00800003cc2a5b6f1b61c5b6d01b65cde2a0b7af2f2035dbb0921db7a4f60aa3f675b4dffd12bf61a6b2eb401974bad0c60d1ea77ef8a6c23fe736e199796cd0b4d29a69288d4d54909fe9a92d66c9d48876fb0b9e3f0dc7faa53310d205608bd4bff1808d3439fa9cbfeae79a27ffc12b6fdc9e8a2d8be166651948f1fd3a76d91ced61010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf5ed2972c0506c2adafd35ae4572b839ba4aa0a57af44db0387b49ccae516eeab1fee7822f6ee961c6344718ab1d02d4fe87edda2b1716ff727f9840ef46e204	1615379177000000	1615983977000000	1679055977000000	1773663977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb07ee11185472f6d11698449c87c5d7bce6888996a09ca7e499b9970ba95084f3fc320c6b17b79af4ad9930d9243f7b3ae3eca0db3f704c47edb647c565a361e	\\x00800003d69b78a0d05c2886734c30dba41233f4078bc270ebb021f3a90d5fd35569c83e8bfd56ce2cf19a3d3ba9c4c95aa5c399c6ad28cdc275e6665367834fd862e08c4b799c8a0784919e61f22f4633742f038eb131fb70c1f2a94addd1f7e42894830e23821b47d46a1325e69befd0b49a7647ece8b3f451c2152c1bc8959e1bed7f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd345faee86d1da98585f004b2c628f1d7407b15bae04968c9244219bbe0bfd0658f1266170cc7c10a6d9fe6d9ded181d78f1d7b3ad862c390a72ada442e1fd01	1625051177000000	1625655977000000	1688727977000000	1783335977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbf36ad5c0a0ca3dd7b93456caa0b98cc356a5eec8f71f9bfca64e5c03d3fbdeb76168ddded648d9ff3dae7d19671c615eaaad2a5023814e238809126c2cb77bc	\\x00800003b3f0fa04d1246b20474c03fc0e7461fabcc5871db0d7e355dcac53a75b84503c1109f3ebfb217357cdbb423ec566c5220780870923b3aea3c121fb2b4cfd324031cfe39c8e5dd56c56bb85bdd364d735ddd8072c1a32fdcd1af25154dc425896001ed3bb83f6a0cd61136628e2f02eb51111d974b13427f897f4de2890b9bb53010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfce979202dda19e5fcee6366e1bbb376cc5dcc3818c552391dd84dc73f8b46c6d7f57c5e31bf6d3063d27f5bf87df59543154dacacd04370190513d224c5e50e	1615379177000000	1615983977000000	1679055977000000	1773663977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbfc2008173b1d5b7c6abc9f1847a35c05915f3548d204be6bb1c82bbb9f5383944cdcce20def2a2c875f3e31f481fd0f3f9e13c91f262af4e64168ce5d0bf6f0	\\x00800003d95885166fdbad531066316cc6dceafaf3dc81d87b1b172466817b35813f11af0460484a10e95f8b444e4471c227c204e8c457bf8241d85a99b5ae56474bc9b83e22a09453f16010c13d61d9ae70f8f73e6072b7c7d1c028e0234857e557173a3ea0cc2f65a7f24e56b6f750cfb91c9ac04b2de103c459b1bccd3724a61d2c63010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa53523c78ddfa0731c545bcd43f5162736e027dad3680b7033da3dddc9916b9d0c8a7b9be186fb785c7c035b1738f33429c30f7f137679cdd1ff68ced51ae60c	1612356677000000	1612961477000000	1676033477000000	1770641477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc0ba4c4072cb79a0d509b5bdfe58dbe61c12bcfebc8b0a461c46a801982bd88866ff605ac268295a5c66017cb1a3ba1c368e25f17ed4aea4794d07500a048033	\\x00800003b62ffbe51db04f51cabb1d720580412fcfb4cb187537e298f3d871be99703f27a5efaaae71da3264a642842a2b5aa93b565626911df49ca289d3f947031d5e999f8c858a92a8a91b3d6a91139c3248d691438dbbe887bfa709d4874d0df290e6426c81ee32cb7db91e53896a7526add6e5b564326723fc0ad92c106f79c375f5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd274fb4a94623b0f185299f92013d9891aafff1151e346bf99b16d08510ac033d08aa7ac16356e5de175aff4e37100fb6a23e34a877541c753ebd0707622780f	1620819677000000	1621424477000000	1684496477000000	1779104477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc09a7de51db6f41b0c452c85c9860b407688a2f039c63334b966e50664e64a2917fbbb8ef43249076e78ce0b69a6fe5375d761857938b44a473aa886338e89d3	\\x00800003a40acaed1be232025c54571b436bfc840fa5aed998cbddcadc3269fe0e4ad6215cb9ffa9a7fb7722b880185222ce94705ab92368698a3255395f0409a49bb88606b16816c478fb1d2a9440a8dfcec84ec5dc221f606c79cba6161ef0eb0190461da6ec0172dc5dacb89cd5e2590d77df87003770f4fe23c3c72ef6566067baa7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2b5bac1ce84c51fdb85f419c83d0b92b333a943cef892c907b8a2667f92136bcdaf430ffa47f02d708468820060e532def3bfa771f0869542d383e0e38cb860e	1622028677000000	1622633477000000	1685705477000000	1780313477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc126f0ea678db83530b03c91018ee63a10443e41fb03f2685eff4ca028076b9230301fc2b84ede277df695b2a00a96e4cf106ebddd156a802e0f5841d717bb27	\\x00800003f0408ec3a1c001d5cf583bb3aad949b76cde4a6dbf63914f1ba7851d4db12e2956193a732631c532b8f7db70a7ca904b769fcd1b7d1c582a4191a328d556977ef90834ad20830c28f72a40d8e937b3ca31e42de5381c1e35cc74ab93c3eda80764f69a674bfe7260d32bc1ef915da0398d434bc2f465047364c36369bc0abbc3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc282f11ce6ed86c8aba0a68950b108d98e116c5115b0b46999a244c4e7a3eafe6ee38a547ee62b49d55edd598e3f60a266044ff11873bd12a6988f43a3b00c0a	1626260177000000	1626864977000000	1689936977000000	1784544977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x00800003a94bd719c6ad3d468034e39c80e96eef168f925dd80fc5cf1a1a881e653c3279681e5c5ede8a6b6efd04ef872463740b0293ad4523b0d53ca752f192be2986eae8ffcb5534aa88f67f523dc676a54809de54800561ff67857d834e306388e82047a5efa30d18284239a4f0f3df3ee7f50a478cc76c5d7b708390da728798a889010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x65f4b2e6d6e651cadb2d300d789880fdb80686091f165836e18d7c6223cd9cfb87168d4559e488fc1ea618a7d75221540c49a88e6168c1764544c63b90f5f009	1608125177000000	1608729977000000	1671801977000000	1766409977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc58205459b4025ebd605a8b11d99d86d0739940618cea71581b8c1f96dce8da087037e4532a07d5493dedc5ede0dc4a5268c5120eedf15c5e68df1767d103f01	\\x00800003d03ce86dbc5af9c0ce4be6901153db83eea35bf49c52799e9a77e120dd53557878357ca2b42c76447c87f191b0665ff5781034d8b137a1b85769bf5d6099a4985ad75d61dacb8b45738a12f56f33331707466c2420835604892e52d64d61e5d7d7d2050554795fdb1e2b18efbc5e093e25863d325ed4c6c5505a980e4c778353010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6f6922fe5b7d98429cb59ba3294615368267d972df83e58f9042cbab1139d66b3b190d7e18e391e346b07eaae18c70001c66c709506739527c496c780377510e	1625051177000000	1625655977000000	1688727977000000	1783335977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc67252868b01a825b8ba5188d2328e95a19db4ee0436f222040b71eff4c9ca7ec81f4b8e4b8c4290bbac9d0e553e7e125a2c9cd6934d6fb9e6b49b5977011e4d	\\x00800003d80bac0346006e76895b6db93196b5055e178e64b7e5f52f4b8e121bd5d98c85f538e326935c32c4f7a5073ba7c734c9e1f670639aacbdc61a8fd6407e207c18de3ea29ec60ca21d9252728c7e437d0a01114da04729e0cb5d97a1a532d47b57c8470ffa188422b163a14295b6cae7e67c571a0902cc1655fc15ebd24a430d8f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf47bca0228f99b376590a55b4a43ce057a922ec0ad545fe0e4efb416828d0380f54de18d208946472fd3bc3a08b98da741f41f2b9fc9ff9745731c3896c94706	1625655677000000	1626260477000000	1689332477000000	1783940477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc3257cfe336daa840fb06d9fac3e9867d4aba12c47cee7bf79144fab100ce7c3b85b9c426164f27a81f3fcc5d9e6eddaf21d4f2e6a9ae5a4fdd0270928150fa	\\x00800003d90d8ccb4237721875d3a2fb7cf40bf860f58529f14555339a4885cca63938e38b65cec7413dc8dcc7a399d91b7cd4756ea2537b0d790e0afca660dc0b8d695e67a337aa64433416aaeff8fea8a0095085d48b7a6a010a4cc11387f6aab1b12f139d95568374ea953e0aa9c4bff41dd377a98c891c8d4fb9a44b9df0e1d27a17010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8d0ebda1e2f82b2de4314fc2dbf7b2a725db2058923af8c6dc7a158dbf3bad783778f86ad41284b3b8bbf9c9b5bb2db73f4c403d39516a24790803208ad55b04	1612961177000000	1613565977000000	1676637977000000	1771245977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd03a9d78b18e5030ec6c8d868351975831a622653cd3b4924007b59e90e4f86526e8a53a60701f4538a6a84997aaafc4ac84913e5a01ae6d8cc18e772e5ef9c5	\\x00800003c3ae74de63dd5beddcfaf04dc54ab1c8ba41798d47bf325c3d9ea92a5d2db8d072dba5d43b0e61ebc38640bf75962e687a71e1a584f1b1243d01dc6602266153d31260789ebfe535746bda092b3ddbffd7263505e11cf694708e8c3254bb2c76d9a5ef74205b65ecad6b19c46172ad08f2358f23fb5b0351e9ddaaf7e1ca654d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7fd34e899b44e01225d31b4106ed56d10f2fc21c840526c845a4ec3616b247526d4078e0450b638f75fed1e7c81b3783ecb19cca9d5e6efe958fe01747bb6500	1637745677000000	1638350477000000	1701422477000000	1796030477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd9ba1ef511579f77a706404b48077b87f394cbe8ea049dcc6dd5cb681588795af225aec2489c91402089caebb593ce19f1b9b0a92dc3c899ae2cf88fa196c33f	\\x00800003dff595d11a7547a87ecb37744b6bacbccfb297875f0412b9061c4c411ae3e55cad95c3e12df1405d0e4d0fd31cdc33c90f39e615825ff4484465386fae134e3f49b61b06991dd84e815abb212d6841aeef58caceebc0fc980807cb9ef1e665ebea869890fb0bf3483c3c580abe6536f923cd2b9bae9419611f5fb2df2079ceef010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc3def04cb7a14a9867daff96d288fef3a0eeecc7c8844857f36146717bbf8bace8586c0e83325023154d07a407db57e6176d7241bc35955c4ef536c248d8d60d	1621424177000000	1622028977000000	1685100977000000	1779708977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd91e7b8c10362041367d57b2ef19251cbc7923cace383d508775e0cd98f5b6f9742d32e7efa5068eba25563e466e561e8c6622fe1382a5213538366adbf64a07	\\x00800003b183bf273bd67658e7dcfb8e0e1a062265a8a555fa35d24c75b3fdcbe277d285d30606b7c86616ffbf5ceaad28c9c7939ce2fbcfc9b322f2b653ab1bf0832bb2217466f66f675e5c7d50e118bfb9c036efe1290552f993db034a13f213ec3015573f262470c8e774b46f6e12b579b0a4e41dbaecb4d7bf0ffa51706921a768b3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1b3ad56db7b5239e936a7de87605122d71bfe3f09cc62600475ffaa62d23d09d7b10c9c0dd256f27996303e528dd6b1161f608f709cfeaa999255478c5bb850e	1612961177000000	1613565977000000	1676637977000000	1771245977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdb0efadb85896089df3ee1fa9ab3e396edb7f3339871afd9cdadd2f313b397d7d7d21cec3c8085a873acb0e8e01c1a6f54c89aecb2230a46b2f34d33c3824628	\\x00800003c2d46ba18faee705b3aff413103ba4ac0b1db66275e601fb5a5b3599b692c54d82e4f2b27574f13ec0ab82d66ae1f91e832dce958ede2a44971a0a1a780a35f87d9bbf6839fa29e169d85e7915da8417d5cf50fb254b7ece864080ba363b633ef161e6d1a4ee2655d6813230151a2819ead8f90f68e3dc84ccf5a5c858a219ff010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc4848aed4f3aaa18395529d0fcc8f5a095e5f60b4390e36180222fa82e06b00320949362069061ef733c2ad3a1a98ac16fba46aaa2066c72c5cc016cf1045a06	1630491677000000	1631096477000000	1694168477000000	1788776477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0b26531783ac4710af53dc407b60f548d9c56d48906429b5d61cf41af3e314783ca337be7efca2a0da3953605776ec57667e11380003d00444ae039ab66b1f5	\\x00800003e2d8bf8ad9acbdedbb7bfd4018221cbe039c136387dea2ae21a0d83a1938e17c5da589072a2aa30f0e7c0ae2876bca3c2b09ad32a1020757b669aefb580318acfb91f09a177bbe87d6ebc11be61f0ca3ae9953943efce36ad8468f7f74f91053da68802a62cf91b8250b2ca8d8c396ab7ff2c9173a97e04032c4c3531f8d92ab010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9fecbae37ae0670bbbad90a65b3f8a2388b21f05ee5d19c5e05cd64df482ee009abd689d5cd89a4f738e63c377fbf49007723949689a60b26e6d4cfa1cf6bd0f	1630491677000000	1631096477000000	1694168477000000	1788776477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe13eef1b3481bbf3da906d9ea04b0b3a6eb3bf11bb8cea736c4e89ae5009a082daf0835e9564fb9b9f7069f13a953aee82858304b5f0c045a6c360c101aebc34	\\x00800003cdcb485db4fb57bb915152e97214795c3b0354534266f5a9496833d4c1ea78b57b05ff8a73c9756e2d10dd8a238baf81e1829e3f2f167eb0926db48e1fc59fbd902b430d98701f84e0bac96fd4bb32efebe11cefe5b31493e65f1dd487eabb27ab5fd17d10693a9c8047857e82648072dab8e025889b0ff636e1f1ca76b14899010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x14ec6a61c8591bccb13a3e3fa78e93e0baa4aea2ff954b56d0a2de1948f6972dcef821d7c24d201d369119c01f7e5ce66c5786ce2a7ad9e28c4ba6563f194001	1634723177000000	1635327977000000	1698399977000000	1793007977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xed9e656be52719cbe328999ebd09a242968736420b1247601c250b6d04204381c99886de6ba14ec8b065b6b48acaba2c22a97decc051cb58527452e9b99383d7	\\x00800003d40e4c61f6c132eb464b0ead128a6b945d27b35b3f1463820163a5106c8f979f7eaac5079ceec6079b780b921ed3db18f9d720f649284fec7d21ed635befc8b53a45e39957341076d366f98dd42daf1d6f328ee9ab370844c45b5537c1eed99c23dc053783dfbc68816ce7177a70f6b8518ac7c5bc697214b749772f1fa21279010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x00c50f463d82957f4563258b4e158ce4c203bd9c8e664e051f13ee994c4b8dd58d274dddff5f28a0c79767b4a530e0a656aa245d3b12322cf32f98de97a70e0a	1622633177000000	1623237977000000	1686309977000000	1780917977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeee2998722fa668068ccff4d7bd90977f7b5fa67320c486a67a33cf04548a3345feea165214b81d88e4770ea143615e61d75a6861c1594cc824ff1df4b427e47	\\x00800003d78c163fef56a21994c42c609877bcdee5d12b826f9c5f8f677d2481baa3ba8acb168936d9d5b43d289ac0c15f79abcfeed0268501206c1eb90fc82d9358281bb83f86f1b9e090fb9d929e08bbcd9e955d53c72d2d01449c3b860051a2ae7944a6d1fcbcd0fc728ee0d03290e43995d143a3c174da29b8714b58828f07cbe679010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc066a66813bb99f0ec482561d1e5f91767d47d736b4470e388d4c058547b94da79ae97d7963e54b1a2bb0dd16480413a9a70e21b23c92bd75453186197c0ea01	1610543177000000	1611147977000000	1674219977000000	1768827977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf08eab2689c4b2596bcb7a3136334120123c29dea303ede8a566d5fd89117af7737b366a9405a576325af6b4d3a12b9c1d2f1e8abfb89b2b271a26ccbfd41143	\\x00800003c76875716bcd8f3d907578bfc78fefb7ae27538a4c9a9a7a65176a6c6b816c21c464fb3405ac7679e044afe077c625475160ea91161f30d8476467d9f41175f1bec04e27e1d38330cc4974cdc69cbb38e656dc410a4f85736f1f2044e09b7e26b78e5458f95f8d8defa04562d740d71cb1e2237b2356da3cf80940ae9fd64125010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe4584bb03fde3c814fbe08ae72c18f6a3aecac831698097b017c9833e5217714003b41798aecb6b2df7ac20ac769fd0da3c65577ccc176281a7545b1fbffdf05	1639559177000000	1640163977000000	1703235977000000	1797843977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf14a351cfb108a8b6c0ee297f2304ae06e35660715f5e218ab176def93629840b6ef83546c0c7a0bab1dd6ac87f0e2f548cae75eb9c73c2cc86ed9f5963c3b2c	\\x00800003d10504179e2a28b5113c14c776175cae6499e17837c19094fdb59907850d11fa28771cdbebb1d7e6e4f0a292d6db87bcc6013274f90bfefb3eedc2ad947a1f96f15dd10edd1899838b090d45854bd44e27ea3f004ea241d891e949e2f3845364c8b9d248e2aeca0b76f9fdfc5299d3cfbc87e2e467b8c104fab69b0030ccdfd9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x901551c56c6e5df6bf5bc889e25b75e7da7bc939a54417cf527a75764e817cdd50a060ab94dabba2c05487c68dbd52a48f04a10f210651916f6a9332e3373f01	1629887177000000	1630491977000000	1693563977000000	1788171977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf64e48d3093042ec32e710852339f5b8044fd1cc04921f180054b3c8e6ead33e568af5680c7ae6b2726520000137ae1cc170f211593d7daafa7df29bb717f6d9	\\x00800003ba343f19f104e771b8182f2a65be769aebfb69cab37fc26127c32aeb1500c95f9312a265256d6a96d111a10d6d4dae92c1dfecb4cf50ea65c34939bd2ce01e21fe07ea099d45f782945d63096d6809070da86549218559d797765b84e0848e5b08556c539b40ac662f3cea162b7618569a8cff1d19bd8a44aac7841b2d7b19d9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb3c8037be3b44578ab33efa51c24de078765878a10e154842180f5d25b36fc9fbd570323ad6c0f9ac0d1672c9feda6d51a5ccadbf58ea1fd0fea22c79648df08	1618401677000000	1619006477000000	1682078477000000	1776686477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfa32e0226dde8eff1b587e0b5e7a1d6fc30e2313c46c5a5011918541d9411eeb66bcc96cffff913477348f347210439451efd44ab7a1c95683e9aa0672b2e253	\\x00800003b416cbed3fff1402fbf1f73a1fd238dbc131f0dc411dd8bfb18e18e9caeaa3e18fa6af96660106f6a4ab4a930e5e4c1035b937d11c8db5c88b0d39ec5415c460d2518a2c10d75ad7ea823888503155621a65c821fca2152687059ab5af9f433524f376a5d72c693e3b564a14005d591fc4c7ec3ea782abeccbb6f7605d464213010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb7d4a42808dcc7398aeedcaa8795889477db28095ab7263cc1e61bb7ab4a1716f5894c75a866ac9baa7f8e8de49567d6513d96da9731c716cb80a6b4202a7b02	1620215177000000	1620819977000000	1683891977000000	1778499977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfbde6953abb348a6980b810e8ccb32dfe718bcd66b9c5dded6c9820f8f5a003a7479a3cd81fe8182fdbb4a2638ab4e181c5ea16a4fcc91d730d84e9440d76a34	\\x00800003ad9c1a7f803f59c1e6042b284ee23e5cea2477efa42bf021e0ab1b109aacb8597dfe1b2665ff200f0621af6f707939d0c4864c89e7ace3e7e997c3d26cfb5ff97edf84a66af05d7cf746c38a1b1d9a03e01170c89f2d1c4202f284d1e27797c48e4630d7a15346139958ccb424c26e1704ac4d1a33cc349c60f5b8167ef46207010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x28b4df5237ec9ff845e3c8358788bb3ca34f817ca64b0f2986d4eaec1087f26e47bdebd3e1195cd7d9ed7154ad3ebe7d0afd17526e6ecb112c70a724ee286d0f	1637141177000000	1637745977000000	1700817977000000	1795425977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfc62b6f5aa239084bd98bbe2cf0fb42cedb9898018c92edfa1ad7919692f862e85a0b7e3d973e9b963c47c4d27e0cb7077908fa06e4397158ea08d134fea56cb	\\x00800003f7cd538e1ad07336063c631b450e374a28f06c3d0290315da4623eca6a9f6f58d29ca8b8d2dc469fd739e30d90390bc9ea4237e6795f8fac63ce9e2715650d58eaff177d7d2392b4d7411698df8b7e6aee0c7676145ead14db2e1b4d752483b76c330bf4c98cb5a5d3e5ecb7e271fa396bbff3f2f1a425d257b85995eca02421010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9e372bdc45f4dad24baffd21fde7c697a98649b0fa8bac97d4f22580c61f7d0a3a5a55e04adb97ec40e9e48c6c5cff360af57f7b1164083e211fe91883dfde0f	1627469177000000	1628073977000000	1691145977000000	1785753977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xff8e10b35f67fd46f30ae500d0bf813859f0891fa30cc85d5da50b1ae7579e977880539ce08bc8a945d2f52d4dac41ea03fc09db44780f2a493051f59224b410	\\x00800003ba94dd6762417913ad429fc1eb511b56b935d3c0407c01279924c8f15058b20d56c4a0a1f0fb9dbe684cb87798d01180434f8d24ca06a01c7effdd5c0b752db60515e66823ad8f1ae5846c904e23ff876a03b8dbf6295e27a2eafbe4a11c9eb99a6666c268b90affdd09ac63d3a4d6dd52975d67dc9f2493d640ff0b7afd5743010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0a9a0387be3c55e532b560a0357178a3819281f251c1079674657c3728b1a2fa69ea156cf2f5673a0e6549c623029de06b0c8df6f36d298ac4c54775cee84704	1636536677000000	1637141477000000	1700213477000000	1794821477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x042377c5614d46c8c9efd34e9f911c3daed587c0bec7796fba1a5c55c9f4a5c6efb5f0c1351c264d2df67c9dc4267ee22dcc207498d3611c68353414ec723d03	\\x00800003bde3cbf37cef6d0d8655d8d83b0fa071cdd2b87f0c9f10e1dcd08633defa9b2cd1b9d62024ef996a50a75f2b4c8326d59340d1a216d6405e479674708f8a15fac10bf80808aba2bd928087d27fcbd90beeebb43195842f699d1b5303b1d87648ccf6052ccccd3657280f9b83aadf6d557c76ca37c26474143c151fe8ef821d99010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2f98e16ae70018bf1846c741cd8aff5607bb9a11c853f3437b1ada15540b43da7403da5bc80512dfc72e461f01bdc00db09facec8951fe8ec147b8d53cc91c0e	1625051177000000	1625655977000000	1688727977000000	1783335977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0563e8467a403cd471060a4115294db6fd75c4e8f7cbd0d0947c32d2fd83613e1c36c7e4748ac1f7a7055135322cc61d24713acfd0115d123f95f62924aace41	\\x00800003c12c9ccff66faf48505c6d4b341daef7caf9d8697068835555fa0e53173b1a44b62af764f927d282ff77d3d74ea395157685975bc9b1c49b164e005db761d5ef92c9266a2d44407f458fd50d4a37d9fb0610ad1b7673598bca326b9810b2df458769e31acd65ea6e1f1a7af20f08e73ac52193275c55924bab3d32538bd7858b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb6ea1ae13d6b277124076f62a437f7b77761bd9d1b4b944d4c5a43590a75450ba914af25e19969d82d248bfa68257cdd4dee9a7df8081a123cfb31c8037bfc02	1634118677000000	1634723477000000	1697795477000000	1792403477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x050331c723c7207b73c8be44a5e965016efcd13aad2d4ef23b344774cf42825e322931a039e6fd69a39095394f12dd5344e8a9e92f2e373f476db555b1e9461a	\\x00800003d90503aeec738a85587a3066e41fa2c583f1c046fab99ba88dbb5d3d60d6e6a51627406378f52d4c803e3134e5ea128fb7f10f06cbd40dd0db19a4a03d3d0c96e18663bcb84960bf605e4bf82d2b23838845c6e54eefae3f28bbcb38db6c1e1898ce6e7513126f91a164416ea699842bdfe4f5710327a4acc04234770b350199010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x16f87c39853ce76680d77b7aa8bc3a34cca009cc59b05c31bb83e652a94f8ee7da33fdbe72dcf8dd3db0c0227dd97cb6b643ad3e5b61bfd14cf432651bf4480d	1615379177000000	1615983977000000	1679055977000000	1773663977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x06638c1983251fcf5ea9575b096e9f7a35c19d180d1f40ff7eb06f8fe5a0fdec5d236a8325ce80690916c771ad0d304c3df1b4301ffb9514b6e611b7ad7b7322	\\x00800003d91bd17b03e1a9ed6318b9cdf6b6c1ae2415bcba3408a8b623ba0a01d2cfe037c0accd197d1ec94e4ef622dc45619f109ed4414f4677b952f89e7e8e2b867e11c610c4460adfda359dca46e6e18379da420a0bcb63ca7998ca3fda3a7709d65f9de0a9689b14c2ddbaf7ac2d0ba3dc67caac01f42c3184b87b298231079e85a5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x519d65fb40864d32a40aaeffbe2a7176162be234d332656645ce05831b49d889acc8e1ed43b178f57f1e707f46810c8451fe90a3edcd77bf7c2cc70b8de4750b	1631700677000000	1632305477000000	1695377477000000	1789985477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x07639fba7e1a355d5a80d22ef2f0be8f5c432e9aea2d9589ede6855ad6bf79c5dbc85f15d7089fdd4d234aaf0cdf157c040bc7bf790c997db1d0ecb712afca0d	\\x00800003a6f674aa6f41139a0605a718abf8a4549a888b93c0f9cbc33a12668baf48f6723e626f9c60cf8f4347cbbff161a13bf69d15a59ca6f2256e3ba119144f72e03175a97ae0f8a3eb12e4f0f04cbeaa83e5ebfa38c84a903565ac34d2472d81f5d49dfc0d699b0b1e6d21c057fec7f9aed7efb7cd59fb90c16e6dabb8dc4e2c8841010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb72b8d4f69f7a7a4a19dea28aee5aa0f68ac39f598758c977ebfa7d7e90de99a67bdacd58548db2be5cf3cc95df79037e5dfca11e4ddd9672c261bbdb2164c03	1629282677000000	1629887477000000	1692959477000000	1787567477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0797873378e3b5b47bced4ac1e6be2e9f1275c87fa2f151b033fa3e2df4d814ab572ec3ff09b61c09bb956d1f96481beaa3e27ab44934ae1ca31c9cbd9ca46f5	\\x00800003cc0bb4a3204018ac81956eaba9e06223036ce74b1ca473afed5829ecc2bd1e11130716136bd9786bc6ce22d3bd88698072929c05242054e885743fd39cfefd5a8cabe3b96459f323da251dda1e29fae42642c1de474339ba0b3f312a6748d33b9c66c90dc89809596987c22890d9c28342c9e20ef3cd325ef097037a0bbd7c7f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb6d15037a99c8aed09ed5c3843100860037443250010d85ecb30c7587ec867f35bfc88b25f5c1bcb2d349ddcd64755f475626bc593bc7f7bc34be7ae6b699a0c	1626864677000000	1627469477000000	1690541477000000	1785149477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x139f1afacace47916a29c73aa6cd6820ead2bb140029508021dc5674f979b33b020d26d84c28d4e4a93b3d478fd465190fc2752deb2d7f2e4c216ceff1df7b47	\\x00800003bb619eeac92866f11f3712b828e8a9d462a15d299d34147da1218ed0e98ce546518b33c13971c1d1be18850e01ca361f8f9d21fc168326a54d483a74555dbb53db91680b6f47c1af5c5a409adf328a2ee8bd25ed7c110ff79692eb69842f8ac3ddce6a55bd0d2c7ca5856876005e93cfc3b69d8cdfd93cde27a075942b3f5bed010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb59e00b63516aba29c26e9b53939dc37a4b03aae5a806267bd848b3176b24754b6bdd0574cd1b66a8388d961bce1e60bf2e8e2bed0425bb630a15a7382df8204	1616588177000000	1617192977000000	1680264977000000	1774872977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1587559b3b66638169835e5bf003a14ba838c3dd83a720c380c305355be6fa3c55e87415e7d2cb79eb27f62bbe1111eb74954ef7bea98f159f626b83210e0c0b	\\x00800003b21c0f8ef6ae5ce4f5639417ba6bb8892a6e0dc22c85999b3ff903fc213a13ad5998be08d106175218e587d6266470ed38c40bb61c9bd734354ffb72e5f8fd695c4165e24b05d779849fcb3710d5ae37702d0bf0a900a5adf1cb0b05b5901f2800269b4fcdbdce9161439c22b0eab2f08ddc18ecfde876fd409715c979f27b35010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd8489f816e709e2ec38baec40abc60745d84e50fd77d413c0abcd5a2508a252e2954a0074ed0d877efc696bf644da8f3942d4a85aac75bcf2be53c0ac1830a02	1620819677000000	1621424477000000	1684496477000000	1779104477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1627e819a1b5adf639dc803c38b1da17f52b8eb8b98ce8e4c8e8a3615b9f055f26b0bb1acced9c01529329948b6908f5f9dd691e737bb340465223c3cd42c1e4	\\x00800003c4ca70e87379ca46d800a762c4d3f1bdf92abaf8c2cfbebbdcf66fb3a6ed203cb0475baf049c577cd75e6bb992b5d72594887cb9e6208989c345275dceb6d1e6fd04d68c56a9a00e9a30c6dbb98d69fb27e296bca8a154080dbe517b2a2d18a5e823bc62693401293405510f6e6b50a22f619802bc311e8609fe0041a5ed8f47010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc86cc4bbe47a5c12ad5f16250f07978d40f366fe37a3cea9dbdb1210c3db710bb0a4b511a6e6866bc8607b6b7feb653a02f4dcda9a05cd61b213290f6cdfa006	1616588177000000	1617192977000000	1680264977000000	1774872977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1a3b2e42def9f11abe396e2f2fd2d33a854d4d623bffaaf233e01848e3a19f56632f0b7a67a91bf8b45f625103b1616df36fde40e2bf0f35845b9cb0aa1211d4	\\x00800003b93a71676a65de2a3ce608ebdc3bed5e65afbc8bc3245e8800abf6f7e5d71461a523a51e2390a177582dcc4c65b04c5d2c46cd54611c15b75de572d0741ba8ad029754b4ad76888a27745c5f95c40cce7b88a8bb9d880123ab52e79411a36d55bcfe76d8d5d1249a395cb1c53579804b23b0eb318357b96a7f70ac633b3b4ae5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf133f5422181fc9f2dc55444221d0c782768033547df9edb7b72dec9194501cc04ee4d008832eb265ee7499fd83686afa296aaf2ca3340b76efe61a477fc3502	1631700677000000	1632305477000000	1695377477000000	1789985477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b8f94061120328d1fe2043bf1cf7c4049d1a7bf31af6d847c21b28d4342ebe4e5553dafab3420f6b52014d91c360cd7e4718c857411b2a3bfbb0eb8ad70c1e4	\\x00800003b6adeebd94977a4be261d6c5188b8c1695eb9187d743d6045603eaf1e9c40135b9e42b92562d15e2060ce001af9114819377b81484722e05f7999c58c7eb0dbb8288f1b0d1cbd4fd189ca3c5766675dbac2975bcab12e3d99f9604e1115bbe045afa191c8959228a3cd080c6865626bae8f2b30de41241c74b8d08aef77c4ef3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xda7fe7b47ff014bef342cd13f7ef71eed2239c32497b6657f1605aabc246da73ccf9bb4d210517a672cc9918d0374f02090311dadee2929c7e95010875709307	1619006177000000	1619610977000000	1682682977000000	1777290977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2477117e8e812074cd4c7c78f3562a471c49596cefe474e1a27d06c0bc25ccae718f255065e4ce4b748815625c7e2f3153e85f8d6fbcd40056850067a68acfb4	\\x00800003b3d4009fba674ec4a4688809df2bca7a534214ba781c683a01cd2885cd5e2192b1672b7a6696977696f97c6c362c2ba2dc556f3f57a8280cfc1f07f74bfc1e691a4bf17b3d4245d533c8aaac2ccd6fe30294f8155eae8b773dead653e2a028de9d00d36da84cbbf60aada2c7018bb6dddc7b0d8a153f1b768227d7284858b297010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0a1df26fa238aae926082043fef8cffd4755ca4e90734cc60c6e311d0beb3b3c5473a742d2704572417fdb28ced870d9b5c74b731c1b569728eec846ce7f8b02	1622633177000000	1623237977000000	1686309977000000	1780917977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x261bab3bc5c99b44418fcd7e055a8b1ba0ab1dac09976b48ba8625e933aa996e46c676d5e58dafd8f34b86be448edcc21b7d9947d5611cc28ab10d4cec8b23a4	\\x00800003d4ad9ff486937882452a15a5e40462ecb53c69dd917a9fe22c320cca57dd181aa7140b6252b7d47f9aa40ac8ba3e13bb495dc8b89ee63d85311f6fb85dd87c2d5e52d42c559aa0334d9e4fb752e49d42ff44506b119a85aac2da15537d367dfb9731fa7b5ccd0df7a0d4825316d2cb073d46ab89bf7869a3f6ea28c2248eed3b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x624972e18b68c8096ef0c5e49658e59c044164e42daf2cafd1d5e0bba34503bc188c0bb620c68980cf69f6e3a4d736d4705c9e600de8cf1e8156bbcfb280880c	1618401677000000	1619006477000000	1682078477000000	1776686477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x27bfbf4d12fa25a3f3565c85d1c42e6dbaafffb15d8d4c40687c67cec1518f068c97ec7cfb2c9bac7845dde23258b1e66c025cfad114361d938832911cf184d5	\\x00800003c0ed6db2063d93f9706ba75132f7f41af01fdea0e818048c84dd8afddf20bfecdb9d0e9e82dc3aff6ff572227940bbd0576dd0a0f9fd676111c73fa4f0e2c55a07c89fadefc9065c8d51aea561245008594e51c3e7810f783c2b1e66d0582aa5c3f4648ffbb85da06e13e23c6b3866028cf0ada3ce931250672a7a7ff749a645010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1109c3d51ef60c7a37538c1d5602b58e712a0a3dce504357dc3856d26c718d6bc7bfe7d19354747e3ee84a2cc80bef30a156cb0eb47924305c97acd228f3a50f	1610543177000000	1611147977000000	1674219977000000	1768827977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2983e7e909f4df35c8277274e88671631e746cb7e71f60a27e6ad82a05e3810d4d530f23ea7f83242145b60847b650520df4a359b8d0f71020a9d67d16ab145a	\\x00800003a6a9da9809106c23da7f9b97a2f6cffa6b01843c4c8b5a098808a27f718a1282829581237687e265927305fbc6cb6da21a8f58acce2ad9c33dafd20ce493d0db45e396358172a8a5cdb75fa3e3fd4202a31dfff0550c97e36bb301271171cb059063cf0132f271c990190b0cacecee0288b09f09274047e25030d5162ecc1c8f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x636ea5e9a1c3a7bc53f3925fce02de6dc0f39c5ca594fa7296e6d17dae9b38064f2ea242a7e586c79d23e59b065952e1ce6d2f0b04b79ddb72373e36b7ba8201	1609938677000000	1610543477000000	1673615477000000	1768223477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2cbf0aa23bd6e11a84b08ae05807c8a496917a52d66b01b950d60809cddf6065977cdd7475adeb055d32e465f707594d6f01777f2358acaf51c26f2110b24f1c	\\x00800003c1d5af60e8bc2556e9bc7f5295e2c2c58ab4c1c83ec57240a581a3190be261de6582221cb17ca3abf5ac30c7337147a7e98d3fa5924728e0628dfdc05a2b5db70af57c834e5833962c9caf57668ae0a5b612ccd1f7a6fbf14eb0ec6a83fc0c18bf4a3baa9e2f89f46677f1c739b4beef996ae4caefe1145c413d2fc0d490a615010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x660ab77f9d9a3523e52d3b6f2ba72b963e69044ae03cea698ba4637b52a5b4d6a8f100088969fa90fa3f1ef677dd9e8b6ae4c5a6ffa3ef78c08d4b2da9f0fd0e	1617797177000000	1618401977000000	1681473977000000	1776081977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2c03fbed1b695430842f0fc52de1c2faa45f0368ab413be3424137b03f97a7403f2b000b9985d2b916b13e899ef0a630dd35fd408ec445c94fea8e979864f388	\\x00800003d89b4a6f22de6e30fce3fd7bf7bbe481c6ad63b65cda06244ebca829a4a8db94bc4d6a9add9d790101cf338059f3054ac5cf7e6cbc531fd80300109823be6d66d248964e412f9d4140d508bd9453b042f965af7659d298e68fbf04466b9a918b7cecc772ba3f473dad802bae979f028fcfbc1557661676c029a3c08d09c16cf5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x79aeebe1d4e4501e388eb902ccbc25fab8611c3c3914675fdb6f7d42b17a90682a9a42439026ffa96d705e00c98ec9f46c6e8788849aab563328e383bec6940e	1620819677000000	1621424477000000	1684496477000000	1779104477000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2dd72d44a2d5cd3f982b0b97c917186ba8783ed34cf7c16fe0e26ee3b4b7476cab74a09e6a681e0241c85c899f2506a9c31fe3a92ba3bb542d252561e1e8e12b	\\x00800003cd5efae83872ed1278e8527910354d58a85fbb46e770c9c85096e4ad338d4523cc21b3c384ce400cc4a1f983c83c906de79e9be393664f05a28aa4c0735fd76d37a660f79dd25e195fc84810fdf03e90ea7cf22c3792cda822009a9c54fe80583904bc371a352000d6e47bb1df4b6aa07f8832cd8706e731bc6e6c46519e1f77010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xaeeabf3090e377d3be6f62fdfcade3b701d93e6def7cca8f2ab287580ea029444a4f08c05a94b22e9541ae65252d0bf29697dec3f18d86ff842a736dbcb58600	1631096177000000	1631700977000000	1694772977000000	1789380977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f6fea8b73c0a00cd7e79a2ea9d52ddb951fbba20bdf73cd3d4f0b45846fac313b8fda160c4f0a935676d0fa4aafc29bb976e333fd6daa155453a8f45acb4d95	\\x00800003d2d8c690658fdce855a8ed4d7943ff5c921567048fe5e8f06b8c293ea141bc077e5ce7645246b4b90557835e55e9780eacba6d7829fa12a4ad7d3c524ad31dc318d9513fdb1b6ccc1ee69482f1d6e0dd2a343c0ae942167f9c3a4264298ff49c9d104d3c2c97ce1d5f01ebc7f0d5ea7686dd8e013d5493eaf81cb9d9707794e1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9c5c2d7227f16cf74395a61fd1b8833f65dfc05ee3075d1d05d2513959168723ce92c9ce25130bb0bbfd1a092ceb83c4d4bc706bf61b7b57abb80d876d0ed001	1635932177000000	1636536977000000	1699608977000000	1794216977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f3fa88c08b3eb489e9a7b0b3733c5656c48b773fb213ae7fc2610fe082560242a7f6305be74108d79738fd3cce052479bb2f743f251eca8868af64d6e8a52b5	\\x00800003cbc4f0c4d07c92a52cc7d91d8d379d2fa130a4d12defefb259f9e142095944076b7d1b03b3e77782f5d80c1dbd7e308ac959a42091272041eedd3ee1736fee704457cb851320786c9b397e7de1173a45d53793f746121bfad0d2c6bc1f3f303d5184fc0de52953d7c88166d8b13f948dc4afcb70cf81d27fa4823e05fa03d0c7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbd92bcf164b9f4034cf26a3757bc19505b25874ec32198dd4c98f78a3972779f68df2ed7f317059026ce0abd0d164d720917f1c393ecdbd3bdc4573a57378809	1635327677000000	1635932477000000	1699004477000000	1793612477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ae77530ca85aef86f27fda26124774e3607b0685945059949c312ec641b6938887d090794a5d939683017f211212b77c994bc0abe2a0c8575d3de6096709a8f	\\x00800003b6d27664e7b2ff5704e7966434009fb5a0923ac01c8def1e94112c2cfbf2bd98fcd59ad62e363b21c1bed776deec5c8f2bc968465d606304d15ed19ca44c5ddfc08386b9fc1a301cda34230fd0e818735869330ef6ec13bfbde66a29996ffa9bb3c77427e0f6c14dadc2dfca1fa50fb8d5aa67eac17620c98d16b3f440bdd2b3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x924c0e8029c8b6f8a9aa4f82065c0d1ca3f9715774f453c986c4550e8f2d814a62be8cef55762f95becf3b2da11fe800e5f2a8d66b5bf3d18beff93dcaac3b0d	1628678177000000	1629282977000000	1692354977000000	1786962977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3c23553f0f274c053db170f4a999729b5e1a8fbec3ed152b022ae5300f5a4db24416a6298c0ef093c02c5fdc5ff3b8ef66f37f7a9d61afcb734195f01f719026	\\x00800003ec817a05cfeccb14e6a1a3456938ab8cac8b3304a37fc9a0ee56b4c08a8620e44312575cc90612d54f9d9bcabbb829edd9cb25090569a5195ac7354f71b6e52da943ff91bfef6586f9c2f5f37d5d43cb7fb1aedd58e4bdbceb22b5144f6484b0f6263c66dba565ade901104ded7a2870fef5b26ff889a6625644eff0c66181d1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3b0364c88967fae97f786b0906a5cbb586fcf414184a6d603fff8743d7419c82365f4eaee308bcb3d0883c2ccb764653b95f55ee3a1e298d0a6b0517e9514c05	1634723177000000	1635327977000000	1698399977000000	1793007977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d43dbc103637c2b94af256ea95b32fed552bf6ec2e4114acfc3bffb79e70856baf908107c7d0e6536f8b3f6f055231f14cdd0dbf469c4c0169ef521160942bc	\\x00800003aa3c18a273d4a4599e6aaa193d8bafc41d04b09541604f7ffd14bc423b22af0ea30302843a375064f38b61c9b1c0ffe316ddc5d8f9f6194ad423ee91e23509a840d5a3a9a98b3d0828b4c826846e771615c514dd267f21f74e2ddd99fca05ac8bc19c375b6bf29d0c2153ba189a283d3e881e9e89462003222748719a06fa8d9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x68882c356abaf495dcc1627133d259bfa4dfe531d09ad0843bbfa5d442b2aa5c663fd93fa7974adfe16345ed050a0ef1ebab468960b7cf76718f9c0283717305	1637745677000000	1638350477000000	1701422477000000	1796030477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x454f5e883a13aa526c9ba309dc6502db21136af9034291e151ef3b2dd336b2137fafdeb69e8a45b1a0777d44c5e15debba91fdde6cd63c51ee5bdccfc577c14c	\\x00800003a9c6dfdaabf10123f961b928f8d8e1910eccc95c948a5a45a010d4293d05d3e12b3d3a4a99367e1360da97fabb8a9a122486ed3bd68ad4b2861b5c1b7090bbbc6c476b64e470e46eda5d68391c642edcc1f58a75f81fd609381f1c845f5f4ad107f103bdfd34c0d00c7eb6b81b7a0e2d1eed1b025ffb7eddfad57596fde6fdb1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfc6dec116cf9a88c1eae6bd857a7d80f55f49cfabe04b83909d57b7d69d8ac9074d48e0775462cff92f3eb264bdffd37727adaed090d23a7b22a923ce4a8e805	1623237677000000	1623842477000000	1686914477000000	1781522477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x499f5d1eb15e43af078582cdf79db319e9b790e62c6b9a2658709735c43d96635027e8a97b81713a5eb84cd23c9549051b084890b31da95ddc66586b5c774e39	\\x008000039b586a4f109aaccd036744280b99e0ff19137d6670a1f09f96d41b5b81b9d1f354c40175d5edb7794f086cba6a2c65c3ad9ac5c685d818b0c184ce4ef05262b8024a4aea21a1efc6a545bebb54c6a56996d9c6bd8a542ddaa6a9020dc34af28835066df21307cd7d76bab5105666e9bcb8d00370e1d96fd5c98a722e7e42f3d5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x48a07e93a049b2f758103bb16be5c9bb721919243fec31a875c714ca407cdd535583ecac8cadbb0fefa8a092a8d342cc4a535128434e42c240f0b7c48c94d301	1612961177000000	1613565977000000	1676637977000000	1771245977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4dfb4763e16b4270347810f1b617b4a5aef59ec649b79b421ce02ef334e05e34bd9d78d42febf9088b49254748a6a1c450c8010c67da1f0e2df3ee785e547024	\\x00800003c0c62eca30735a913f302d2e6a5e361975b6e3e4d0ff6e4a0826f48157bce9b84ba58593d3d46629883026a89a5223e3509d24a3d2d14e9c6739dda67c623258d01cb45ba91585339829196ce222dea33b8ea8d34cfc6f3c9091b0230467fec96ec87a843f59cdd273c866c963fc68520961837d242b75bdc0c6b7470b60d9a3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2f451b78d0c7700826b97d0aafcd5c4f6d343fbc087482650f2d3f56aa6aa94dbecbb9f10b0d9ee0966b97ae5321df09531ad3b264196ce65ef3954258e4c709	1611752177000000	1612356977000000	1675428977000000	1770036977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d8348f17b27288a6f28d196f26feb40d0616679f60127650941172c19a3366058757220ced1fe0da427263a79ac723dc0f84912561de92717922550ae82f696	\\x00800003a450515b313479e193ce9482c27146d2b2e733b23a10522de667b9a075c551dd26dc1a8d78192dae2a9ec6b6db9c9c7200d6df6b8c9241b6988adb8534abefa350659ad2a434bc9d6d0747d874c4b06afd849444ac0e9fa8abfb42d22b532f9526ebe5e4173ada4b0ea46fe5390152d73dadbb8596ede96dbd224c199c10a1c9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x551675018fc83739d4ce725a63609a8280a9bae52188937ae691df0399a3dbb71adb5b2ca275729beb0b5d90c8dad9ff3219bc1f164c8d8187b5745021e04d0e	1620215177000000	1620819977000000	1683891977000000	1778499977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4f4f478068cc17f3eeec0facb5a7ef32cceb362e286a1375bfc2bda8cf558018e71593658810df7153e334078258146669b9d66ede43dfbe337c4176e06f1a63	\\x00800003d50e8dc0b12bd084b8d208c72dc1a9878e32e1d3397f022a084079f59f0bb2e068b2481cf7c33aabc16744335cde6d41599b96b411fbcffc762923f7cc7b5ee56f4fb9393206ba03c6d961783cc3d9a43661291389979f73216b7e060b47024d6555a513ea2899ad4dace47de489fe6d652f8300952b735d0e99687e2d6e750b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x788c9cd7c4ad78cb0ac379ee24e0d5d8a731117fe8edb701bb7ea5ad63362957ce352df59ee9e38b73b9d42a5efd87c00053119f1f4f0c8646f1e9de57e9bb0a	1611147677000000	1611752477000000	1674824477000000	1769432477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53c3766faa3d31a4617cf6f6a2d77e1ddb7d1c14ee4d8eef1dc4a3bd77c63a7461cfb66b020c6a83b4d632bdb239c80f41af0acc0dc72412d46e291502f5b74a	\\x00800003e85f8983e7e008b04c6a41d41b6fcb132ed7fae5b8baf602cfe583f7f26c74315855d73abfdb55fb3d45d97b82a1efa371afbaf54e5ff051d7c7731404f9d7c556a506394e734c0d33e9d5fa0cfb0de975e413c545d8ef9784d4810bceaa2964780b08713a85aabc19057f4ae3d8f5706d82be92d0ef1fc181fef1c64e949327010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa9b5c5943a94580208e68abea9ae9a31bcafc89dda58c8405c7aecc8ff450c4bbd202be9141535862f7841617824a1ea82b4d09fbef3af7f72a66761c562bd04	1623842177000000	1624446977000000	1687518977000000	1782126977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x578398aae68eef2aebba78b044c3d4a68276e53ba5f1df43e5690226586dc6e0dcfbc3db21266b636232c8c62043f0a7146af61b1e0cf484a06b93d557726f9f	\\x00800003bfb75b449da5a55beeaa572e43c20fcbed6260fdee5b63c517c5128f94846097e4c21a29e6d92c01af0a658a19404950f094018b5303c68bf7ecde242780eaae2936e4258ac92763fad9f88372f6addba4fada3d4f40adac95363ec5d99119063c0ebcb79404688824bf390b79232b6e03a6d36b35e0cafadc8687af73a5197f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbf4074b34bef1ff9a6fce636fb69b5f04258ebf53dabcfc33e552e5ebd0092e9b87a91a2fc0b0b94bbb7d8757cd8bb76f6b5d15536fd43c4cfcaa9a2b26cbf0b	1634723177000000	1635327977000000	1698399977000000	1793007977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5ef74b4bfd218ed45b8528dcb74823fec608427e516891acfea99aeccf609b619ee84c7d84581bf5e42413beaed2e38ef11a2c4ac90bc00d4ce1e8603cdeac31	\\x00800003af9d6331dbb3f70779ce275889c600e83c88f28024ffaf25d3ce6150b5142720f6e761ff554bbecfccabff5f3732ecec62a8be868a8f947aff8ab942f9bd94167aca19e2060ee752909504ccba163ca92b0dd9f28c14f561f161c7b64b6b0e89af75065b1f6483e0c97dd289b5b9533b93772078b8ec52d620b607b27e991739010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x98538cd7b956370f8a87e29238dc208710b13dd8f21a5f73628beb68a75a9ea791a35a1cf5e3b196cec5e284affb076cd651494a29b7a5401d6924df5e4e6d01	1633514177000000	1634118977000000	1697190977000000	1791798977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x634b0740da86a9e70b30e586bc31582356353b7bf7cfe309b4bdf3d26f081d2c4f31aeb442b2bae3ec0b46df443434b7eec35481ea88af07982586d236b465d0	\\x00800003adc843a125b83e195417571b9d671d0ce6b842adf087e54a1d7ed04e16dfea2b57737299e41b832d5b5c339e27c458dc904a07cb588f6bd05961d18347522a4626812cc7a3a025c8e4e25ad33172d8a05074ff68c237e9727eadcbb7bfd32d7cec7ea4abcadcaa340a695666255139df922d2da6a4644539b88c43dfe78f2a51010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb6b42a5871264dcae29416ae8d2b09697fbb7cb0b2d478e3632f003a6eced8da3ff24af7a84fd2144207ec906a6951ee031133c4737fb108db21bde7c704520b	1628678177000000	1629282977000000	1692354977000000	1786962977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x65fb6e1028a1496fffcbca210a6d9cc02ccb89bfd0490540f37348f2a68d6b79cd8f4133ecfb5b4ed38d361c9f6e01cf6804b15f3417d698727417a7c533354f	\\x00800003cdebe87dae9b071b33c40458e447f8e4a5c300bc99ab062c16b22d33ce529ec9c29e33e1bfb2f00508f6f8cce2e0751c8be1db5ade1facff62a5f0f85fe733a75da101cd86f9033ae9516011692bfed8da1cb000b5cf9b14e744608128fad03a310a755e55f5c3ad3f0c2ef5e5728b82f7fa6eb6809c5c3833caa50b15289caf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbbfdad567c5a40e07aadf6586fec7fad581e5217e44fe52bbb28ae07f4fe4e9de5ba5934c0f7e567c1420e06b2f2c99d9211f39f45adb4fc91a35be31cfc4e02	1621424177000000	1622028977000000	1685100977000000	1779708977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x656fff611c860c6333cf7024fc0814bc2a862f14faf185e9bcd5400eaf9b6c7464d3bc51aa886a08db025a803ed1e6a831756a78ce53cd8c4e7958bb9cbf83ed	\\x00800003af8f3b5f01977da57ecfdd701c63fa308aba4a5f915e3eea37b7dceac068ab8cef70822f38d6143025d16d4b1ef3f4c343037a1c6a0e3ae7af3cc6d98d965b62f88ed03078ce1693fffc30113a2469b7a187f9b79a30fe17c1cb1e14db2c47fff51d737db6df3fa01c0ca9cd2b6ab4f770c7ba573529412d13e7e9df755b7bf9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xcc285a8af77a353cebc2fad0f7dc45ff997674d9824e268abe7d1096aac224d2b3b78a2b72fb22f8183f24f4a0bf03598222a7a023bf673a33f93625d1197207	1626260177000000	1626864977000000	1689936977000000	1784544977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x67b313e7b94394ddd556b589cfc41710f160b61b7a9c0da52814b1f8e2ec01a23a612511e8d3c5faf36b502705537e61cd119f222a00959b86b7020f388d493c	\\x00800003b10426e381ad13cae0a10c8274087ca0812f9fb859c23462543c30a75e41fad466cae27b8960d41a55d9ca9d042910fbce78ad2cfcdcff178dfd68d13c91970fe9208f243dbc48dd96fbdec9980f472c672aa48c47a2ed1b49156f6e19702bda66dc0f680522e2d7e8aa4c6572e17028cec8bf522de62b0bddef5e5773e33e6d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3b294c1160aa8881787af29baa970fbbf19d8ffdf3684bccb197fae7eef42c3b01198184c6339b710ca4bc31c2479abedc9c084feaf863fb4908b5d731b66f0f	1625655677000000	1626260477000000	1689332477000000	1783940477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x68bb570231121400e5cf6da5d92404a8f0d766184db14393da091248c5db2d9f6c5892d03644096e82a6982b01e77afc94792e746319920ce4cdd6353abc2ff1	\\x00800003c61a591d82aa9b5c72d3ab1c482716886f9a37634eba3be9427992a13d0b07b60eabc86d04728d17400ef1b8fc1a92b9b67b86d386f33602f5ed067bc2c47555044778a0a527077220b45d05bea28d231d2447332c2523726978ddee90a989023ba9dceb06a10bc0b85c0e42db3d598193fa23806c3d964c3b410798f2d207ff010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1b8a8ee7ed95f901faeafb21d29a9fa1706c73e152531f7b48daf248b4a673d81c956e14d4a36ad772f2dfd6b5e8b6cce0162313b3d2507083cb804478df030c	1620819677000000	1621424477000000	1684496477000000	1779104477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a7369ecf11c9a6b27bcdcbf58d1c5b0f97545639cabefd565c2666c3e9f755c7da242741293bbe038eb88c9a99d011001c29ce940660fe2ce37cbc562c1339f	\\x00800003c23aadd8d3081e46637e2d0f68af7ed8dcc396da3c9fd9e3efd46fbff58781a45610b7eed3de7e31c0e2f6fa0b6b2cb918408f306b6bcbec7e2460d3ed9ff24337fb957eb3400df68f74f6a3ebc8d6f9d2e8a871f5c83567a2368bbd08efd535b5b12f396908bec4031146bcaa33e8eb8bff6e1b1fcb8bb8a882487b644d6831010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3b711a1eabb10321b10c8f7dc2eb3f7ab863d52172397b35f3aed3f21b6a314ab46cdbf7b9c8d969ae7627ea273445f972781e49cbb50034e31ed770d30a2f04	1616588177000000	1617192977000000	1680264977000000	1774872977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x713fc047b5f89cc9057d021cb3594a62fc4652ccab973e6b5c2264a6646e1f33377d29b6e12a6328083af8979957f8719bcd5d9a550c16a431f6ee04d7796acf	\\x00800003e08da6fe1261257ce220ae67f8ab11aaadeb1af698fa2d7b7802f31fb364d20434e6dfc1f766be647a5d6e14482d7c54357c5955637a38efae4e0fab2c77d02255b2456b94d0b0816dbb95fa099a7abe131bc9da417664a708462d68ce1a327377867e2b7e57971041ac8ff4f075c50be69d64f19b778deb9d31e8bcfdbe50bd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0fcfb307d66e459fe2869208a4b8d76530b4d0797c6b797a1c7e117513f972fc5aa8f3cf6d7d8311b07842ddbba3c127291b1d3d59b7b6455de71e9c85f0190e	1637141177000000	1637745977000000	1700817977000000	1795425977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7127d71d961e4a72ab6f8c8c43e201662b94d8ed6e9f56fdedf1a74d4bcd0d4767fc1ea95a6144e66e900c2ea2275679e6c624e7c2847f23b41db53de05029d1	\\x00800003b7052711690cc46e748a27b6893f8ea7dfe65e9bdf669ff9476464ee31e159e2e5f5c47a8fca36db48405b6fb3de4da0fa59c82d076f5015e6ee2711369aa2e093956670b52f86f970d828466438a6e1a26e24ed19eaca4e2a26399e9a4e6f2b4f4ce2d72aca117b0d7afcb8c25f8f53042f571ac5f57c6a261bf43781925ad7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x77425e0cf01f931c4ad7e01903a0af4a93d98f89d00166a41d15362c8ff1180cd23e37b86b6e9c012e28c21cd8004532f73ffb9bf7f504db31d2aa8b45177c0d	1608729677000000	1609334477000000	1672406477000000	1767014477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x75a3f87e30355d03b028c87d1c6751afaafaf7050a53219ba913295e7fcf6c1ba723c3ffa7c12bd12a8ae9159f708d53b46f28978e3b8807f3f4985c96c56d23	\\x00800003be3636faac6d3377c74017ba78a4f64e4eec76044b45944f490c71a90fe67f477533e08d5906b562c834124cfc255cbeaeaf9851951ae8d09767b57abaab5dda3af3adb48079918ddb2ccbe6a58de988be5f3a5e4e215182ec7baf819a2d24c1c4f63ed76a5c1a87020dfa6050fa0e5dd35e072ffa6016fad0291fff3442baa9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x24003032f9823a139207a19d65801af6251e1e25171fb4a782c0e66c6ab8bf47ba7bc5ebb4c863f3513f018050f28fb3e19c21ea720bbbe530b82db48603fa0b	1626260177000000	1626864977000000	1689936977000000	1784544977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x78eb31449ed9063825856239849997e1b5b72dba2e89bdfc705b1287dcf3007e2e2f4a3e865d3c924bb336da525501460d7d60f13a268ff8996932cd876d4e32	\\x00800003bce30d8bd0f3fecce064a5e281a01952d2441cac165317d0bbd79eccdb2f608a0bae5cce27433036e4021b6de41bf2d3da4e3deb56db50c7dc9af8d24eb43fe7aee6abd755874de2c1ac82a3742444520ec022517bb75dfd03d8b86ae4c2c83b829e1bd8c9d7be3cd2140616e58bca3ddf0d5f0c8c833272511bfe10fbf13193010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0522c2c005ba39c97cc884375c917994d52505be2329e754515411ffef758e09a36a7d3d664869257c13a709df479ab699afd26e108419baef711c6be25f430f	1627469177000000	1628073977000000	1691145977000000	1785753977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78ff6a5aed4dc7d4f0022bedbc9bedce05347e7717589545faf26a9b2d2544b44e2a73b22dbc71e1b03883d4d99245b6c8369decf4fb75a1ec87271d92507903	\\x00800003ad5320138e2424c54c8b27ab5fe5dc9fb77cf4c190dcc2e117a747bbb82eddf4aa2458b22b1e67d3e2d38f3bd92e0c0f3624037089c86e81b103812446cc895e6502427358d71552b522213d701ca5b02cc684f484c3fc0f0e08f5c8c91d3fb84088a5c993c0794e494358f283475a19f6f21e75cab09dc32ee87044681844e7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7ac49a5f20422518c032315dab55436329cee46698855ae2f91ca52a27eeaf43f20652018704ab57b64e1a210866499e740459cbc57a05cc71019af3c44ea00b	1613565677000000	1614170477000000	1677242477000000	1771850477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7b07d0b0a1bdd428c38c44f3da7b94d6121b8c1e783c19a0197d5fcb0d3fd6b4b967e03d2c5713aebb39676667260c26aaf98dd60e537d02c209b0035ce42342	\\x008000039e86f2047ef903557e2b14f50e8d5443f8a7e5a028cf3cbdc9305dd4f95e6bae906d2eadb5e8dcd7949e6778a365f3e132b4da8b2cf101d414092739596e6b33c14dec3e361c7d2cb4fca78859dc5077cbc9bf67c0769432fba66202baba8f1d0889395dc95b3b17a408c143bb0054607dae8ac884d905a9c099e1fd04811e89010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb9470acc1bacb4b13b1c9cc553cf276f39fd2af19432b4101480e6118a3bdddcdccb46550a8b3678e824db9fd0431c4b75c546176a4160b54e7176cfb5fb3301	1635327677000000	1635932477000000	1699004477000000	1793612477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x816b407eb1a9028a5e1df5196644317f98167df3f2ef96c3d55cbbb4d32f461d1759693888964d1bde5fca510c18d6d4373ecc47507aaa73d65724a32e420b6e	\\x00800003d3e3020620e492b4ecdb9937506885658c765ffc05be50d3a5d737b472747ad26c738bf227d78c87a0500a7c7a0eb4f9232bc09e51dc9a9aeff6e25ffee7f22ba3681cffe2fac92d3ec780dfc7c8ccc4b2a54ec84b129302a97af9ee2a48d13a1c86d5cae8dcfa65c822d9b3f011bb62e7c7a0a848144ab7437404a8289a33dd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1a7d4002b1286fc55b801e81a91fd2245319383e4dd1fa82e0fec91f0240cc1d8c828e52b11cfb588f3406570db959db2fcc398ae2e72c16de07c82c78a61c0b	1622633177000000	1623237977000000	1686309977000000	1780917977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x84fbbd65274343a2e5ca7f7fee762035047853e58bf6193687523ba65eda58463e3a977bf9cd58a4b5d7091925c63019bf76544b3d0e83d768070d85445fc2ad	\\x00800003c673a9ca0ac6d329ed1e2f8fc5eedacededea1338aabd85448dfcb13cdeb6b3fa3926a6f96bdcfe388adf5685b8e9abfe1bce41d61de5a565dcb747bb17f81906ff74a60163a9797f7a3bdb4688bc5c64d696864be2ee6400b807ba947617356a5c4c373ecb7db0da22d1555cc1672045f3d27ef3b99630011dbd94d2f333f87010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd79741a3ca3d8e4c838b5568ef6026046f03add62f452fdb0b7a0f48eab964a45c8cbcd339e52248a8e151d1f24df1565226c6398434d5ca41fdf26f87ff790f	1631700677000000	1632305477000000	1695377477000000	1789985477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x86034ac0551e4f4f7d2ba5be70bbcaabe1653a089c133721ac764fd44c8c948388b6b621799ad2eae6baf6644f7570118aff331b50815c75b51fc5a95583d94c	\\x00800003facb32c3870caf61ae307b04a3bb800ae39672ebaea013d66e1b3c3f5b710e701f44a1bd3da0e649eece47ff5ae82badd943a21d5621655277128ef7fb8f68a2b03aa809b1a360836c5e4c68e170f0125d400d6043a5bbe3c5e52481465172bbe18be8d985d667cbf916e2f604617bc96f898b573a46426f2d80d05c72164851010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6f2c1586b5fe3d9c3fef42baf46d969e581339eeb1951547f3ff90d6296c4ea54dc42aa06d41dff4167b0ab6b80723d82d9eb513698146a441a0a1c3c6d43c03	1638350177000000	1638954977000000	1702026977000000	1796634977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86b3745c8bee52774f63b4debded65987358c99abee4b3a73328f77c36abe2ac79ba641c7d8e01b67920ea458595d16635889a29c7d003419e88b6c4a5284837	\\x00800003a09f57ad47408d2e2254cfa1bfed4dae3ccca1795260fde4d3c1fa129d403f024db7d0adca573f99edc8ef9e3faa3c832b1ef7113083ffafa3bc70797c6bcf685d1d64ffaf870b2cd3c3e2aecfad55142a12ca64096dcefd34189c259e935cdce8a5e4f864054542f0307bb07d66e5a1482d6da2f53eb86aee7f65d59539c485010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd25ebaf86dd6751e1de7b49118cd0eee56dd0586036b8eec8820d3faca7e7461d1654f7e2b16c75a3b25cf37bb25090e366f3925d14a870de13275b1245c7a03	1627469177000000	1628073977000000	1691145977000000	1785753977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x87472dba8abfbac765a07d4d97ac429c274f4e62c7e53a0a9ebc03bb898a787cbc73ce525e874f9eab05037e0e14e62d47190e8f6545b8aecbad633b0b6aed65	\\x00800003b6ec28e3b679e26f8b3ec6b0dfa0635744eee54d32b24f87d40fd7c5bdae85b821beb81ce9c73ac1f72d3d7d08563c01b72977ba8f8c7bb3a563b0ce1c2e05b5bdee5087e4ebac4675b78a470cf3e64c068e470c7355687046ff8177f61b14b17b166ff38d6a6a95180955611626b8bf6ef6ff18785751a58ebfd3209694b5f5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x9bdb887bb06a29258a3a2e549495ee77971a983e4b8ebf4988dd4ca97c26bcf12d73c06c3ae0314234735039c54480dc6b51b372e4011e6a11d6da4bedde2c03	1639559177000000	1640163977000000	1703235977000000	1797843977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88536d32a76a10e138d83d771df8b472139fa64db5459257a07c74a58dcc9f317907d6badc1342c1a61021cb2335c412f6d29c6a3c9abd00c91bdb03ca9a0371	\\x00800003dac4c6ba3da16f3f9814233af93bdc9159e313fd7a82ab288e94e3e2a463863ef1820c2d19eeec037b35e27f580bd988c0dead1033c7e6a43be96dc09249f3e6c59f1ae1b737ace62e29aba08abdf6ccfbaba4e5a585b2070c251bc7691f6675f4268d47c3c2b6186efae3d3c37cf3c634280358b77e489f249262c6eab05759010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x326fe8e70d85839283916ab8c2de8f8368787747d206d7843994c90810fe8f743eedc5ba70cb799586e3b402e739196b2f4e8c24ce415f4568ee0c36f8dbce0c	1618401677000000	1619006477000000	1682078477000000	1776686477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c9f4d85e50e7ca14d216faceb8778c3a27d94bc8a5d1013cb2d439a5fdd196f85d39da225f88665e0b46cb121efee7d3a6d0cbcfb29355191d72b9b149439b5	\\x00800003cc2f96853c5392f08f97f3dc41d90244562db256f4a7e7db5deb437eb4984c6b643a11ed837d1515594704c3b1fd90b3db28569141240fd49a2f0d33fb028f294f7e3f6baddd5eba9ae8fadbb3ec131facfbc8f518efb98a0c624c00308ec7a9dc940ae43022d631d7d1107e97832e21e97c8b07841251d6a41f30524322fd7d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3635fbd807056a18de75cb38e3ae20841c920a1cc2d33e91ced37a663dde266655f64980b80e1e5ac92d4695f8d488f37f5c6e7244b298fb8b8e14928b2d300d	1609334177000000	1609938977000000	1673010977000000	1767618977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8c1b4eaea4b77da9ab670e6848c1c7ebb9193c2aa40da1169cba60f8f02b8d4852b5c0e74453b066692fa4325b6debb938a015acd9f1f8e88c0c94ba3e851849	\\x00800003c0173efaf61e10cf870f1115d9b2f5c8ea1e43e424cbbf7f6a0918541f378aa14dee6b85bd135a5fcccae7151bdb954dfd421be0142436250964a293e3b458221d3f2def4ab934f1368a47f8765920b95eb45144779f64cda910c729d527255a3672ef78a28fbb1edb6fc93c3a96f63621275cd1d55e2125a35be8f14cdef57f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8130ab1233c8482ac0f9b3c1b5e4dda55343d99f3002f622b763d020cc2c04129ac6ac4ac037134080472ae49c2fe4cd38ca6063c4a7839c5a2328505105f70f	1631700677000000	1632305477000000	1695377477000000	1789985477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d5f278b396a08edcb1ae9d4ed87755094a54bce3246b7aacedbed5419959c775cca7b3c2c194076f9ea6d4c8bfab4539597e5a1e815fb8033d713bb0decbb67	\\x00800003d1a6a28d5cfad8e57b3acaa8245f33224007ecbeb688613cf3046c15ee999f6ad0db927a9419337ed3472d4bf8d296a8e39e8457d3dc4e98b15ccb17f7fbca240ad6c4059c86454b8a83fc063b9e5efabaf74b83b79da8e4b0db1c4a023d5197db8ee1db3bfd95bff39e4c4c2da8b9586eaa85d729ea7b7bec19692e25fd94ed010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5d6e43d2b8ffb3878e15a7026204bc26fca662c0f3840979aa481e4beef1aedb7b84f3cc7aab38a3ff5b07b67fe52d48434307023939bca8f5c4ca9eb1acc90b	1624446677000000	1625051477000000	1688123477000000	1782731477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e57bc17459817951cbd6330217cc23b730a7b37588961c3fb1003647fcc7849f4671285cf9a4b88fc0c07745ef1322dc2c1cf0d0c0ece31cd24080d60a05cf2	\\x00800003d0c85168461244c2a77a646efb81af35cea571c57b4667b0d0b4c2a3cb88eb875c0a20bc7d53628e6ace20ea54d2a76943764284264bea1f238b399b67172b9bcb40e4b29b676ecc57615c1f8a6fd700315bd6ad07877c1bd29cfedbe78589b3c9b4091ad8d53f2c1e563bba8ba69620034221b307b49125eff9657c30d011e7010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x0a8fd5ddb82b8ed7d6bd42d443938962ed19bdef447c7d187f055042b4770f71430750f2332c7c627cf481f69e55cee280271347bb2b54e93790f186dd7e280e	1617192677000000	1617797477000000	1680869477000000	1775477477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x92c7c09ae5d5075b6748d99d0a7b43897f981459ddcd0c91b2708c7d3f41316444ddb38e11f9d0d371894373421ed39665232b47f929c87de3893d67be2f88cd	\\x00800003bb02071a040aeb8c2b6f7bae7b1831c8d3868de7f4c188deeeae660c066fa9895a1343e6699815427fbeebdcb03f16822e97b3dc35b776db52840b1c487fc5f32195f9941f2ae3e40aa73359dfa60451400a1e25eecf33542c5a45ff53a1f12312582d1cf98bf6297b9369f23d7f73d64cc46df616831c73b4933b3961827c11010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x4fd921fee8c6a4d28edfd4ad95c8fc431a428dc71263f1a90dbb90a73b651368b3c2ceabb9028f5fa49327ae59edc8358c127e3b9e25804f7ea46844eb403005	1620215177000000	1620819977000000	1683891977000000	1778499977000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95c77845de1112d36ca8dc936b15d62a12cd5ad81f005ce7a6054738753c3151e8f55c526b5833cfe50b394047b62731e7cafaa2fc66efb415ed6ea383fb974c	\\x00800003c5fa7b32326d8c5ce52085e8418b1010bc652ca5ad9166f9181425fed79334740ed2962f1905e5594fe31842bbf70709607c90fe712df063cca1006bbe40182f567a98bcfd23d2e928fb0b4510341e6b41e492e813cff571999f55a1025a7a421b02649ee115927097bf380e9437186b545b218aeda277e4e8843b878eb5f3c1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xbf4a2e8eb1a8e1be055c7d3fadf84e13fc9450a69ba08f850d85a0de8c7e2170ef7d75553894bd3f22c7929e79fe9183f913d0fcaefca9c0d2a5f394bafdfb0a	1627469177000000	1628073977000000	1691145977000000	1785753977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9673333d6b91f5ba7a5fbfaba4f3cf40313d7ad2710fdffde22ad4b61835fb6157cd4ea6990f23699f12d495b1c2209175b41353d526caf5123a9f10b4bc993c	\\x00800003c2087c0089b07b432d2c23559e79f36e28a1ca3cbcd3d2ada0f9a4893553a636d213ce9c772359786a6490cd9e921e361ad7c8a3a9021ae4c7a87ad0dca476acfc0149677c1202b6cf190793284584471c78d4e37b9ebca6e5664593b730a7d0491c36fc70c7e75bf9e53da1f3261086224b8282d710141b2b19ea58fbbf500b010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xde8942a6186f6d570f45e88594dba6a4e606a0c4c1f83463d50047b306106d682c9a7312a3aad9177ed82c1b5c4051c15d60980d969accf86890c22f4bd54100	1614774677000000	1615379477000000	1678451477000000	1773059477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x97af3b1a22a21c696be99d0508e0ad80961814b363fefee86f0776ccd8a6d835af4eb8d3927d7583ad40f7a6c7ff73d122e8b0ffd0a839438b6d7ecbf1eb51a2	\\x00800003c7b25a9be04eb7080af878c44f7252df738b7a957f7fd2d30789f018494fc1873c9ad0a230433c5e34375a6fd7ee30a68fb49523d11a9388e7631b3b327d8e4b76cfd908c5f66c459dcd41ae1b8acd24057c6a025fdf459b8642dd8ab1491e19fa01432c78fb5e4b0d49164e34af9aab07f44338f5e1467cbe97c98331f6f5b3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x21a7ea527fa1533dce2b47fad2bab897b9377ce9c32b1ef36cf463bba1fb77a059a4ffe512fcbba032f397ec93a38620a552ac3d3228c11f911dc50669514c0f	1608729677000000	1609334477000000	1672406477000000	1767014477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9817e754671fd1e05bc92da9c0c22cf5459f2240942589d7394cb63dfed8511edb20939c992115575485bb0700618f95d6e85e9d568c71783927534ea33f3883	\\x00800003c755571da36f89d43a3fe61ef889a1366fbeb02bcba70a45e05a32dc2ba0faaf418a6ec543586e0e9c08e1c12b1d46931e311c38c0b9b66265dce3cc3d07136cf9b2907859d46ff0deb669fb6df31b003f833c800b85d902d945b935d8e5fc7928495a114e247f6e33fdd6fd01ee974d2b1cedc6b2ec6b6ec48076a821eafbfd010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb02617ac5ef95a5c797695883b1b240a3257b671fd9dd240ebb6edc60889d694648255dbbb267cfe88efba49c9be699a59a59c7cfe4950244081fd57399c8900	1614774677000000	1615379477000000	1678451477000000	1773059477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d7b50b39cac9febe2230d0958fdc21fa9c867e742819d0f8d69ab120f0017dd48a0092e135bf1bba1153f127ec529b70491384bd4af43dae5a8ccb935c2f377	\\x00800003ad0d24731fe042816b2133ba130759f7e66563c86811ae0399df019d472be3e9958c22434078b0c89c5d80016516d14e33a2a3cf463fe8fdb80ac665b15870025c0986dd863832faf00c196272ada29388e007b1b23caac3879c37b060079c1ebec8f1af0adcc5a3c9f5471f10a5b0cd221ba73e025a14270e5b68c18ea5da95010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xba06d5d576cb3b92b0075c00880b24e1320205efbd49d6284f3eefcbe245a5c54c667fa80fc8e17277013fac2366a3a31bc817dd60852aa4bda0add22a648f04	1608125177000000	1608729977000000	1671801977000000	1766409977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa38fb045cc3daec8d129ef7c7ed0439d1cb1f999f60903b8f5de44beb9dca2af6d2d25532f481b82448f99088877ce01b8aebb19474d70f4d6e0fb0bb35deae7	\\x00800003c9e37c180af82f59a25918555d73b396c8055b80230cd5de5e0a2af7606b2725f9b78afdd72150c8c191197ba9435f410aff7a534c05cc3015e389cd33fd4f9e23c116a0ff7b0a41c68606eee76c62fd7250ff6c2e17be348f1537037a998cd0654cf17a34226b926e7b4dbf9b849acafc1233653c9ec8bf1054b8be1ea0c2d3010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x63ed1a0578d7d3aa5166f365f6c17668b2178f018aa31020185396a266990cd4e4d10fea36d0d92966422ca85cc169122c68e99941052e5d8e7ff14344c9f007	1628678177000000	1629282977000000	1692354977000000	1786962977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa5c7e06bd788a4c94864099570624ef05623673371faf7349b6625a32a7377047ddd89ab3affaa16b97819a08161d08475906382976401590de77cf76bad8f0c	\\x008000039d701e8503978ec8fc04f32bad65eecff5bd1be44f9604cb101e0d09b15e3ed48e92011bedacd73fd1f720365164a7b37c5cef7b1e19710055de057dcdda1011024d5219adf938d4321ed1a9a2f0aa06a6477fe0b27f8ca11dc97a0ed0b17d1684ea2a0c328f8a09073a4dcf6851fcbaa7a99af8ee3c0627ccdb82c957262983010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x95bfc80ad27dd4874bc6dec2c3160d93cb8fc02e18fe76bae932ea1c6382a122f8dbc03a5f3c15783a55fe240c86881d6dcd344b4359188d2b145d2366bdf106	1621424177000000	1622028977000000	1685100977000000	1779708977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa9835f31e94bce4bf13b98f35d265e4a621eaf47b6a0b0b10ab8aad1973e6e7dba89ccedb4f69bf3d96bc5b4cbc8338523392d7e206f1435fc4c7b45b72044cf	\\x0080000397f7b011e55ea159aa0dbbdac39d7a1936b8e4364b457e5dceef7d99c3c52ea4ccecf1c6754b4c774dcec8f2b493ceef67b22658c032e70d665d8b0ccd7bd3ae2b290b74cee5a5ad9c0b06dac1d2d4b73d26d4a46cbd752ad40fc95cfa89ed5c688754d4cc12d6ca05efd3a6a9f3fb201cd23b2f48a09c921e84281c017c228f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2a6a1b308a874f20e237b73460b74bce6ac4a16d8215bdb9a939d4bef26b0f201e5179f777b112360bfe27241aa438a42aec6f33482f73c7cb271fc2088ce608	1612356677000000	1612961477000000	1676033477000000	1770641477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaaf7a6f7f415d17bf7854998e26f985474832bc39056dabc4b828bc0f3cbf261370a35420e9f570eb7245a3730601c6a8d08c22eab991655d8245607e9010ceb	\\x00800003d4b85089326935d7f7b00ae04507be05e4318f44c664625f1f83ec867dd0a91efeb1ca2419b62b2194c6783214b93f054663ea50b49de5daf6c346a5789e182f1f15afa192346d82a0358906eed93996d25f6f509de75755d770bab2a764273ee3848f59e9fd4986e241ef30a3d5e0c9eeb886c1f290a0aee3e50e65efa43a11010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xff52aef5e6b787da6f98712dcac3e33562a6c9eda46b51d7443e73ed6ca8cc363cece13fa70ee111d1e6fb9396639a35f7bf8518719447698c2d9d98baabb504	1626864677000000	1627469477000000	1690541477000000	1785149477000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa77847d684c2146e66d932ece763bee2e28d4c0ec63040e6918c2dd9f413b1a04448256dde654c06446e41637961e67f8fa37efe3ed0e32ce3fd1140a92435b	\\x00800003df85de9eaba0ea04a394dc3e7f58e1107b58ba64da9c0ad34ecb6296caee5ba841fd2505677f137a212eda8ded8c3f642d3653ef97c7d13507a026288de96dd8e2bc4e60741406f1ed42eeb2583ca209fbfb0b20bf537cdde7d50ba805604c582bdf9149fe61242be82d7bd78b1dac255eca839dc2ee5d10aebe281e0dbb4e8f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x583750b8bcbdab0b8991990ea5d4dcb3117ec49f02cf89b8746d0af7d619013b780a7ac9d947776ec67744dfad88fb1b6c1ba7f7b2cf1e39c1d0086a29425f0b	1625051177000000	1625655977000000	1688727977000000	1783335977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaad35934e805291a7c3915552c5e6e0aa84615978da0ff0ccf2bd7dc3210753dc026a8605b2f63c03d32e00531639024267d5ace45e6c4db968f7f058f67698b	\\x00800003c9b9a86f2f91a722ca8035599e71395f986e6dd1e6b63678fa6c718dd647956a4e3d982d3d9a373c479d3a187ec39e5cd446c14656d4272c13bbf57b3e93b376df9ed6a5b619072033602bac6839b1679b44d37c533159be265831c357b57ef86242766fb24b22335f65f106399d1582c2eaa7a03ebf6af3b2793d0d3a8e30ad010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x94af6c2cd78f990154b7fdae997e3a63f2681f2596ae414294b9d6c0ef1b7bacfaee782b605f3d850c7f4e50a74bf694bb288999ae91341318c04e223ddf670f	1629887177000000	1630491977000000	1693563977000000	1788171977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xadcb3a47b108604d7cbd00de15744d05c36b324f8b7640962df66153f210e0b46093c30529bd23080e1f2227904a24a0218ebaec819bcb70b3f3bc55d04b6f1e	\\x00800003cd93cc3067e8757f14803b8941fbc3f78d9d8d9880f39604154078d5997d22dbec012fa014791df194d1177102a7f66718c5b4659feb109ba70504161272d25ac4132721f4f3dd6d402b43052f9591818144bbb38dbeb28a722671b5c0d528961a14c3d3dba9381910e4675cbd61e211a193a1200e25ea63e49e361073348d59010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe6e05d6b6afce8889416096bc6a65250ea3962c2dcce13b910d3a004b8b4cf930b99bd856a73df730c5d3ca15a2664c205e08006fd02fd6b0ef8fce62f14750f	1626864677000000	1627469477000000	1690541477000000	1785149477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xad174b3f80ba49c67ec192a7921686dc3c05763f09abc98d7f2e6e77ba7667cafc513663857a80d714b9fc525a2223660fec0459159052f2ad9fbaad4479eadc	\\x00800003d9c5ab9ed59a42da4c678960bcdffc4c70dd421588df33bb80ab338102129dc5f76eac0bb6688829cd3cf44b1468e32e4644fba16f0a20885b6a6cd299fa5d35f4845e2faa3faa6ef6248747b3b731263e3c31de6d1b666d9c99a70e94048f6b1e5d8a525b07799551423a6211c2aba92ca77236d2f936d5153267887af9b041010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd630444d1511a301b7858ec44adf5b17db47a1ec0fb009013525d173f1388a119fc567c2a048e5cb50cec0499b9938d0952d464a5e75c72236cc231a8d1bfe0a	1616588177000000	1617192977000000	1680264977000000	1774872977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5a70c25c09ac93774b6ec46e8bebfa8cf6ef185dea2a9d6b929c334e1453f1297fe50efb49b21749297298d2336d8f86d2af799d1c7320592ae1e9b0d56b82a	\\x00800003b9bbf80e0c155a97fed3eeb0d1e19773ac38c3854f6e72e404244312bd5caa441a422b650776305c817b979c4b4e5975c417887880a616f928d17926c3446a2f2bfec9354e324f558724d0fac5cbe4abd4d09306d53bd8dda628b8936090160d5efa007ec313a6c03bcf657d8f741ae9ace9ebee3e430db8a849c4c080269dd1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x473f1e2784913e107fa7e09bc5b6b2a4263e05171e569094987f389393e95fade7b0cd1ec055b54c85d9e442b3c54ac4ba4b3b720dd60eb07536f449865a1105	1633514177000000	1634118977000000	1697190977000000	1791798977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb58beb9479ba6252f6c8e1f7355b12c5ec7fb8292bf3bdb2356601963776e5525171c6783ed49df2de103bc567283b69fd688a1ed122b43be74a465039a81b34	\\x00800003b94c4cf50103f26fd0635c75b00f74b7a827c9576aab89c230c6ed711da6c1e2cc139fc7365375d91fc331bb7e2059c533368ef187cb97a0dd91447b80397ed73007f16547e86420bf58e9714067ed963588f7ac42fed9806ef6643d1d6adbf826ad9bb89bd5f23c07c648bdcdbf2d9051a982f6490f1e56b82eb233ec592c49010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x5a71da4b4461d8d9ba5d620e12fc67b95fb90accd5b54543d7dadf4b77ffddabe6e7c743afbac8e8009829bbf068bd72341648cd839194f06efd312dafe36805	1632305177000000	1632909977000000	1695981977000000	1790589977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb947e342d12730a7af9113d8e65a7a7b90bf9d6f6925667e296de73bc22ee767e12f6ecfe8364b4c9b269a098aac04fb534290908f2443315bcec775b4980a42	\\x00800003c22cb04dc7a52d4f017086a1ab0a7d39944217907c6bdd285b718c67564b74ec03be80f91303f28073ee7bc3a9beeefbf4895593f3b21e05c37c407765e82bab9b9c48275640fe1920159c1dcd1afa23b02ae48dc8b451fc5ca564bb6c82e2d046a9404af205433c4efe78080c2843a2ad5ac0a4425eb0f884e47f3900940e35010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6d3a1f843fbbe64fae6d69b3e5dba0028dfcac661f234d5a03072bcbac3cf9e79d4a14cb9464676595ee9e0de1b59402ac3e4c4abef980ad59b0613110e49906	1608125177000000	1608729977000000	1671801977000000	1766409977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbadfbdea4f5bf222e68c3c5a5120de696a6420dae85c02525167251a45f7a8ac5702744f0df32db46636311d3b9998db9b8ff3aee5ed9e5deffed9014d98ad7e	\\x00800003b7cca1be1dce663edaf490d0030704b892f7aa3c6557e7aeef075f3b2662cff05d965e70240da75e7955f8f95dd8d394343ae1de1b3d823d3e4a3a89d623d34293ac89bcfcc28c2d1d04f8d0afaaa89d2ddb45af1e051863ee8ca5c936eefcf840c6f3cddf1c317027770849d80e9b544707ae91822afa349104aa211a5f73ed010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7aad3e5d55b3291c191a8c27cf50761993e4464694bb4cba69687f26c38f9158180a9c0582b58d91b1bd4c6a4a47d1338ea2b1698512ef6f94cbfddae1845d09	1634723177000000	1635327977000000	1698399977000000	1793007977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xba5368e4d1f18cd7ff96d128977e6a433e31c46dceb0566febcf1d63fbddfddd28587cdc83015e65d775daf96ee907f0211d2d33d88be4088a0635c655e00951	\\x00800003c70b53344cc309e82ae85743bf2b5fac12684a46864b448c9af97236c21f96c13e09af9fee1a7ca9440e5113894edf0a9086e351a8043c11b01d6bfccd4844e5eff931faa17086fcda6168bebd156fd2f577da0912f3500d58cf35f014e43582d946a4e35edc402780090c19b3aa85bea059a6c930b30960a6b63fac8fd8ffcb010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x73cc9febbf74ccfff52473f5b8b0f971af0ee1d64857488ab8f28ed6d10b96949c0895cd240f7d66047eeafc1dc8b2d21a405a2b5e572a38bfad47412f508e0e	1633514177000000	1634118977000000	1697190977000000	1791798977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc4fffabcbdbecb485491f1928232fe0fd3a7af9a4805ff0dd2fd38e2f856f51b947f56f004a99f29d6a036e027e2260ad7a6e2235d57a844bcafad1de756701	\\x00800003c2484682bad81cd9251795055192744fedbbbc8bea771bf8ce8e2a6c54b9bfa2791cfdf13954fb55aec3814be8bef81436a65300050775dde7dd9160e53609f74f588b4ca818ab62057dbacf078a7402fbffa1b9bd89dd34f4f5d54bcbb557779bade9ba92110cb064b509d2cd3b1e18d7ac0aa8a3adfa74261e64bef00aa805010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x66cab2f8fb03bee35411007a1a712024dca2d26c742f8974ba880630176589dfac5bb379079d952a3ec542652121b4a6217975d25746bbe7712d3819dfff2f00	1614170177000000	1614774977000000	1677846977000000	1772454977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc5b05592cbc5ccace9a45b28f3258f848a32f71fc6542ce03cff20c85a2a9f4f04ed51c8887b16873bf4fd7a0b83427d8beef4ce7865f463c2a6c664f418988	\\x00800003cb8cf9bbcb2cf439f54bbc548d63a0cef7decf23563381fa72bcee0643a0b399937f53dc5977a32a59a4231dd01cef492e374a20c67e39451c351f80a9034f5e061a12e10295b058948d2ea52ad8fc768b7461cd50935412c9ba4457041cd10f62f52cba9fd1122b6dd569b228fd7e70f4ec6e58b421d3efe90d691e6ad85fa9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb0feedf53bfe26f0d6c6fe6ee044240d89aff4d6df61c0f21d88bcfee6532ee0c41c0e3995a00402f46e297b16c7af52f49fbf0ac542a258b5bc781844440f05	1617192677000000	1617797477000000	1680869477000000	1775477477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbdab05924d209250db1378362c8a7f0eeb129a3b7f9738ba3f5c6907dd4778da8dd5200abe247407f43dd55c89fd6fa89d6808bf3ec3bd6e51bb85490659166e	\\x00800003b29266842f3079cc82a35eb3742f9c8e44df155334b279fa480b8945f72f436a5b74c6e0f29ec4bdaedc78d4f98a79faa7202b3221e5a485ed1734f4ad7684a82441b018343280b1c5f8ffbf776e29e55a04aee8b0a98495a4456e259b1d059129c3bfdf0b5c6cb5b5a9c8ef06e8fe375f4e7a466372f6acd1620c3272a048bf010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x166ccdd119bea4e4eaae98518fbd6b6bd764e4aacf3efed0b399797adb02011be6773823b67d0440a1d7594bdbf176f825878b2b4c934c5edc4b9e7a0498e101	1617797177000000	1618401977000000	1681473977000000	1776081977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc67323590e9d5ed0b89b5d5baef6c050a1425bf258f1cefc74df46b1014a391eb944af2922792e6c89a05ca710440565131d8bbf24b628655b278c4702c22b92	\\x00800003bbbd44a767cdd2a5706282f862cf7034af09bea07168bbd3d8e01e0e4e72001aff00b14af1fbff58e35f2a3e0be2b0f9aff4f0d2cf9179e11356e1c124e0fa79507d80ae663299bad62b0c87ba42b81518c468cb47afeff25b8af627280df4694291ad0c61ba575861620131898c0ce1ea4de3662d64641c5c20d7eb990f081f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x3fd02486f9d31b876d646e7cb6d6689efefb07d440e0164ea320c9e1e387083bd3df1c6a1ed53b0d52217299c14d8de2135609dae421a5c9e9d3e8d4ba1fc009	1615379177000000	1615983977000000	1679055977000000	1773663977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc72f550662aca42be17255e7866087204505a5b825c5d4f8577c706cb9f580bb61eb96df88309fc077ba7cbde3cba006a048be1ab863845b6807b15b39ff9f68	\\x00800003ab5395dae4266a08af34110ddb0d89fbd13cee27c7ab1184204a8ed17335ad6c68050450c938afb0c567d94d5688e09607a5c15f80972c7cd9db328532b677e766fea79b9d7dc068155c732bf42786ab9d7d2ea0ed1610300bf7c4e587fc1f54ba0f237043d717684d2207ebebe9f5e4fafdf0bc787a352972a9a72c46e76b57010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd7737bb7cdef54017dfccc4aa041a2b2f7c35c3dc115580c77787af55b03f104032e5a557ac724e6abb3a46003a4660c941f76760e6b243021bf94cdf712a803	1635932177000000	1636536977000000	1699608977000000	1794216977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc89fc8a2e38da3c8c04f82aa574efca5da0549ec09f17a4a3673429eb75fb49832b0e5e3f4c8559cfb337682103814d799bf21ce09e8539f7216c41ddc7ff1b4	\\x00800003a57989fced0a751fb0a37c2ee0a8565806dc63315056dc076b775ea69929607ca244d6f8595e50d55b81ce18129c25db83ed0a80cf3a898800c74cf156f956403c2a92474eabbdd824feeaaa3133948b93a2e1d8b50cef5d39ef356af6494ea88b27c383f538d543d3f8578fc4b7982e13beb87d547ef090f0b23db24e65119f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x35ff3192dce2dc240c557f4cb0fe02a3e4fde7432e80311b4acb16fd49b74ae9ed0a4552ec485461fcee2bbfd50047dd9e500045ee3216d7b5d10cbd8af0a806	1610543177000000	1611147977000000	1674219977000000	1768827977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcfcf6836c54b123eab76fe65ece23d4bb81b06dfbc271205ee13817cd3111524741741683850a866caae161e2aa7441e20a47eaba1fdfd99a0e881a28a3fea24	\\x00800003ac2c288eaa1d140a066bc581c1dd4cd8736718067f47d310d326944cd97f3d253d1ab0e10dc684848ff11c9bb6cb4cf929f224c606d8cae1490f1f154c4ed1b9185a2ad9505794ce4498c397d42b621d6a7a31dad7ec275c12b60e549c22872202f75f7f8f17795cbea263ab4ea3b6e3ea3c6b990a0e84d0021d1315d609ebd5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xcb9f4c2a43ff925b21b645489046a3658ffaf3740befa4ead3311f36380b3fadb915e5985890a61ac2fc37d092a5be35b23c266ea50fa4a111c9b9b7aaab8d00	1632909677000000	1633514477000000	1696586477000000	1791194477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd42312e6ed2c2acd8687efc5d5e67af3c698969caa6b006efb6a56f4e30ea7ec514045b4dbac0e3037baa960e9884569658e7023da37ad7dc05a11b4397765c0	\\x00800003de3e8b0c131b9645bfb83e3b56450cf99055bbd43bd0f0626ca87fb06a52f5ec0ba559029825e01b2ce9f85982fed210a28b65616a31148c0d40703d9407ba4e20fd42a16b6fed1532a93cd0452570d6a39b8a44922768848f39ca6d1562deab153be1fe68e42dea7ebf91502345704bc5ca75a3220184971a91b22b9a76c037010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xafb58b5816976e4f8b7f2d8f96260b28626d1a98b098f6421615ca1247b5e6266a3345610ca2c6437b6eb99fdaa10143dd1422766de872e0f2fac93226abec02	1634723177000000	1635327977000000	1698399977000000	1793007977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd5b7069155021c1294cb8c4263d705e1a734b2217696cfca3688b73026d2a20c54661984441ca752787f83a66acd99b5e1ef75bedcc9563f7259fd1a61005d87	\\x00800003d23587d6bd351cfc7d941df0799ba1a343e2d9314343d8b5e74c02e1c29d514a4b721299c93815d4d00074431bc7ccab1fc729820057bdb588c59ea87e3301d92bc2e5040b64b20def99637bb49cc097d31d28d950bdebc9da03e9fab47629098e946f0195a8d4fc958a2320063e2a4f274f03d373a3e0a2b338c07900533277010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xc2da33575d879cfd1c6c7323c0fe93aeaa8b96db023caaf43939d41af67c6518ca2d272ed4a003d67ef23a50a950ca46302945b37f14cb1ab8466c66a298a10a	1637745677000000	1638350477000000	1701422477000000	1796030477000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd7dbdf99454b9a8e56f4a7a7d48550ed882752792eff90da413ebcff0127c8fe023d510e5a306f5f6e18d648c73aa20168f4b2a9867fb054808a7af4b9612745	\\x00800003c5c3dd975773795972b132ab0d38df0e2a39820d24e756ff7cb049e1b3801530b7eb93760efc8cd2b6188e62f503d7c3cebde4c44a2f4db4909a3c921d861792454bca6beb2249fbc494df4ed648fd9083dd1e33cb1c5385280b8956873b89e880156705c73abb2573c90ac3c0e814a580e86dcab012860e90a27349e6036101010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1385b956cc4ca2848f78cf47e6593f691f9fcd547b46ee4dc5ee78c066666b7584b2b9241709cb041c30dbe408fb61d77152f4c0bbaaabd119d2993a02311500	1623237677000000	1623842477000000	1686914477000000	1781522477000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7638b8316738f6520f76f00de4ce8aa001f9b7ed449646192add2e48ddc262b66e6ff782f86fc67c10a00a0756618ef746547330dc717cd83a3ed29a3e68239	\\x00800003bb9d7947c12dac003b87ae2c014ff5d19342e7f4588b392923ebba088111bc315401a09ba70937ee1f47ffb9f4b101c311eeeb05b1b3e37947b35efbe695cb6960b8ad9f329a278bd295f921d7e398d29e8a7da26eb83ec40799e76c49ea2a3798f228c4c0a4c32fa728bf27e5b51e0ec07044d9ecfd88dee3ee197f70d7f5db010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe6bc93dc1879e04e1b144683c151c60b705ebd8fd66bfbe23d86231254e26acf26e6d9765333b2ade3300533ac0e69b1735ad682a08ab1e86dbf988347f80302	1639559177000000	1640163977000000	1703235977000000	1797843977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdeb712e19bae82e041ecd1bad4f3dc9f6e8429fcd619b9de8116a6f805eb143b33ab3086a2a86c67a6b92c1df560c52e8604ab5448852805ccbbeace0f64f726	\\x00800003b745e179a116d58e587bc9b90a3de5a3e7aacadd84669f219875272615ca901208e65c991eb3526ff52feb3c07b17b2f92fcab05ce85489cc0cc314fd4c8923c15ec99f60de3b24973b3df35c8a4f505e413a493370320f407b432dc27d02568199e79c348806926786645626cbb1a294ec9d3f99a143060815fceaca16e3859010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd7c79dfa098e7c4563223d15dbea67dfaeca6344af342fbb1ffa0506a477f905d9feac22db22d5bc4997065e7162d0079f42d607ae6d0ca41995a758d2485106	1619610677000000	1620215477000000	1683287477000000	1777895477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf7fb965b590ad3cd202ff083aa1c8a29653b7ac0f172faa6468fd9669bd26291e4ab0e652b55f02cd44d7ec86b07ae5538c6838bfdf135b47b8a5e96f23327c	\\x00800003c9239fa75e271be4c85841ed3a5a1564e8e8651c455839032114432170628a394e18172ef04abae62a7e2ef6ec390d8e026f0363615c06ac2669c5ea8531b1de1ff284c56e52fdf959055780a8f93fd95030a8682323dfa4de05cbd35e89d0b397fcfff5a5fef9c62d3297a985ef22be9af755a75859c99dda67fedc0fb9f5b9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xa3643d33283ff5ec804bc85421bfc0a9469aed32ae48c933a9ed856f2b2dbbb55497fd28dda134abedb310577ae3aeb181de23e9cdd6242f0e7bf54ea3c24c07	1612961177000000	1613565977000000	1676637977000000	1771245977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe5d7d7186ad641e1f584e6f0f0c745fa8b3868fef8bb6c39a7461ae62cee16fdcf294de84918411ed3312b872702e01b3569ef99c6e361e174b6b789a982989f	\\x00800003b4e339842230f0ba7b128e7c92e54f259ab985ef4a3535ff1a0accfec992d12b6f254fee6584f738e10a3033cba1497fd1d206c57773c40a9d30fee92819b7e699086c24af01e4e9344ef7e3387dfcceda4f61ed9ec93fd58dda01b5fe28ea62afc3ff20aac6c52b16b44f500411df08983aa6c4308e6f4c21634a75a165735f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x32f2f1597916d91df62229686cb3d513b9a9b91ccb554b91d6eb989b57cb95b150c834f6ff10cae74fe9202f81b302c368cc2f08878c14dc056ad2492f9d4600	1611752177000000	1612356977000000	1675428977000000	1770036977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe613dcd1b78f4fd5d3cce9f70830d825cae9ff6e19c5a9d385ebb9b8ec2231a663f615843cd6dcc663d820a13c153cf4a7b186a49ab07d32b2703a143b25b69f	\\x00800003f951ca32581856dc24e87af1933f2f16944b9e07626eb6657bcc09d893b0209d4309c05f0af1534d769f964ce65762cbcaa5f033471593d90280988bcd12f76a8c65402a375478a626e99bb55c00327f3e850933c3f48ac9913cb0501d0476e42b36530a376c23010e0fa86d6f37285a71d25e25b5dc7271d9c646ed42de7c73010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x43c0498b1019b9964a9c0f9146f030053ccb0a45a30ef72c6e4ee38f9de97c52f30059f8de3883b6795b9f900aa70da07e9758424cd026e24047484f5a28ee0e	1609334177000000	1609938977000000	1673010977000000	1767618977000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xea23f8132d0fb86163ba3d7352b48afb443f5cca508c5e03c838efd2086988512c1ed60d4725c8fa985106ad27e4407991920a4ef31b73b827b6ef34e57311b7	\\x00800003c40569e28fedce48ea6874bb2fd410fee9480e0f0fbb6e8e6166ab050569d2dc3e59ebbd3b4c3a543eb2f7d9b30f7796a34c8eef9a9621d9f8dbf01417b0ba6a08c36b994ed3660ff1d66b5f3065dc61ccd6b71b50b81cf3d98c7d21eff4eb3e9c9e4d358b20d1fd157d36b5e98cf15f1e8ac834b6eb58b5d98e528dbd2ebf0d010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xe3a94483ed4dff57bb77331df556f5658086b85f42473df4a58337c3f91cd4a30bb14d631916a8ed32ece5f7c5eb24970706f2c798b2cc3ae0f9e4442a0a830e	1631096177000000	1631700977000000	1694772977000000	1789380977000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xed77a5c078e2b02f6aaf548c28cf1f6a226a0f5231111cccbd40ca94cb1c6f0a31a8f4a2c8a727995144cc139cd9db95389fba4ca6b49cecfce320d1368a188a	\\x00800003ab34f128c471710e7f89792c17204a8e990bbb9172616701399dd1398e4e92a09a16345eacb74befa28027524a37c59f4973af83bf3cb3acafaa1d9896f2752c5c4439d1a9efb8bc2ef04e514a878723f7764bb90d555cb036501fdd912d866c0ca88d48566d76b5da1c33b3d51d81d0f86d9bdd9fb2acada4f45cb6c7f950a9010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x1cf1e10256b13f61ce1d62acfff88212a3f82e5f489fe075f7168bc9cfbcd4bfcf3d0e91cc3d54d70b62ab5aea65a184e81199728e5dcace6e7a7b70e31ca80e	1635932177000000	1636536977000000	1699608977000000	1794216977000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xefdf89cbb30614af4f1d879d3d90b21e263f023beb26b38feb3df2175656a480828dc70bb6d1bf24b88c60ac9781fd76e379c2c9ef420eab19f11d46977f6888	\\x00800003b1bdc288120826eaae8af59e0cebb8392490103d4ab22b2d1f47bea3e1aa19f4e8f22e4d29ab8c5dc656a79c01301d5a991277abe089d147617164735a34c36b0059a37707603defa2f93de22dea2e741093767c0bbf0a195db2f338ba9f7bbee729d0870fe4b9e4e38fd037881ee4f63be0ab59263c2a81208f07babbf80a47010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7922e03ee6067cb65c55bfc68f1e915e01706ae15285f4db785c84656d1002b73e7f058dc6fd9cefaf24ce796548b2a4021c2721c861b6b9fb8ecf370ff02d0e	1634118677000000	1634723477000000	1697795477000000	1792403477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xef9b910b59167b60e86f9e38e894df28ce4604b883cc0c71ceb7f31d6cb5aab7d76494a996b08a7197adf0cd7009764fef59fbaab76650a7c80c8bac2c565658	\\x00800003d82086beecd8243f55a3fe9f1e0885020623abbf04c45e895de6d128621645eb418680c9b8339d7e06fc77c692e396121c994c7ff969a7663367077eb67ba7beb0402b25476a12760b5895b53c8c6e211558ec91e19d63bab64268101d6f8f9e8d5585dadc945c5783ff9c20c611511782ba56348dd21622ec7b74951933e65f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x706e225ae87253578f179df0e933342fe4a594d73c032169661d83ef0246f9db5b2ef1c983532308cf798df989ffea660c8f9a1e8f35205c691733a2bfd14e07	1615379177000000	1615983977000000	1679055977000000	1773663977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf16bed396d4453edd00aef91acf631d32272c741f05da4da4ccdf624f492cec5331cddd460820dafaedc7df51371e850aa40d9ea7b5688b065598648f1cc923e	\\x00800003be39bd3c6c8987ad9af2c9fc8a25b89db0daaead8161043afad283b6d9c8410da2c290d1e5da781d8dc1aaa30565e94ad09ab4592681acc193d45d7fb3d94f8d30da5e0e7fbba5c5f3286409242139053698034cb20220b5d241614bfb2c8eb925c4b09ed0797d1f38aef037d1fb5c62cb4ddf6a75e05aff8cf101d5d2571e1f010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x6d4e77251eb596510364dc4ca142b95a5a1f8064f8d2cc256d49dfc00ae717721f5f74ae3e87e321484c9a67491aa9366b6912ea8ac42c56ad575074e0109b00	1636536677000000	1637141477000000	1700213477000000	1794821477000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf4974696a777deaa588cae1569965276b563ed13863a47cfd29b6e3eb02f00920bfd2c723ab2a14d090c7ddb1d1da9b08f9cfbe300f1b32653feb9a656968e87	\\x00800003cc4aa6ce7e344f0cf3c6d4dc1acc44cfe1ed0285ecd2bbcb34b17fb8c89f1a3f30e9cc8119e403a005b14643149aeba731a550a9f9d8573a83ea386a9d7bbcc44fb41d877d48c5c2a4a60c84a3ceb4aef9c0a1e2bc903f8469da9eaf4551972d9f6ace82a5316c8533752087763f53cc42560ddd5c54d784ac64ee2b1a659f73010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xec056ce1a748b973985d847c0b23be00aad4b256cce392bf10ddf271b46210110f5415e790e3c6cb71c3ec478d58e8d35da84f9f64e6e4461ce729a9dfa9590f	1632909677000000	1633514477000000	1696586477000000	1791194477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf63393089230e69939df31a2c23be7b9689f10078fa1d9cc919015191d1305702e13ba956f4165507cf01308dc428ab320ea3bb0d13734c1cc29e77bf34f5f9b	\\x00800003ea19456f4d2dc094830bd3655869af4b9ad9baf9caaf626b5b0891e70d111af66f0ef95b733882ee08c8104f6f1de99c97358256ae4b23b0491b8515d339a2cb249d95c200e3ebf5b6bae906eb1685b92c4e8a289b7494c4197ce0a9068601ea33cb44c04c26caf2f5da54db1891ff200f093054913a7c473440d694eb205655010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x8aea9ce7c2eb5cb3c8c6caba6fada6481ece3b8278f3f5a4df5fc240fa434c672195bf2f6e8198b7a67dbbe65a6cf277f1b87761b71ada1e964c6713ca76e505	1612356677000000	1612961477000000	1676033477000000	1770641477000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf90b9b3c5ab4a6b878a4c09376d792b9933fc844d293a07a1de2a15e019e9e7764f37ae34a403f54386032e26be5c11c274f06a69503d0dc2a12e4716ac3a240	\\x00800003e77cc148af6a4e8b813692bfb9ce97c082b3ee58caf3d83897d6ec4850fa6d16bc89bf347b3a4490798ce05d06940ee4a9eeed77df714eb9f5aaf37e69a7e260209b26855130e9e5900032096e666f9d6c6ea590f95b8caf59e3be098b37f2807da30256b9b3ec646a2550ccd6bed13c014fd49f113e4dc7d157d2b05ba26c17010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x78c55f1cda4f7d1a3a10d9ab10b6b22494d09aa8e4c373d69b110f6af664cbf206a8d6cb68b6356579c53772f5859e3be1f60c7bf38c055f12af5b51dc7b3b0a	1638350177000000	1638954977000000	1702026977000000	1796634977000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa8fbc540921092ba32b8c817df5195a7c815eafa15f5e265e4b1356dfa7f09f03bd30622890b52a9a203c6558007ca7f3e4ad6faf2a28cf1776c1ac6d1cc177	\\x00800003b96093a9121956dfd2adfea8e016d14de936a58e9654a6ea0c831bd2073bf314bce8c4d8caa0debefa5df3cd841e50dcaa070864ab512aff3027ff11134ebee8d6cb49cced17f80cb2760233f97df506452ecec58f1e0b60253bc8e8f513d091de2ab1c1eeb16038a01a4c3f92ebe96f593da87245d27d3ee47e9b21c74130f5010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x16814afbbab6f9fda1a37eb060bece2a8622728e646a9362e84c1b29155d0a934d434df8073b3d7230bed35501823d42a7dce5b9d6501ca5df133ac8fce64007	1619006177000000	1619610977000000	1682682977000000	1777290977000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa8f8d36df9890b9fba3810ed2759b26dc91b400bc949d4bfc379247eaf8c17d80fefa9463d3ad083f13a2c4cd84e6603d39925ea4642989edff86092b1a1533	\\x00800003c45596878aa22159b700499ecf36f71b5cc9acaf34a657e24f995d58c498c95a852f59010058925e2be6432aa4e7d679101c27e9cce103ccdaa5b53328cc82fcd6e81121c5dbe120246c4a65cf442b47d50fe2fb1b75e8fc894bd9d69c284fc06fa237c5f4ff311ef4e64d77dece6ccf318de64ff15697e7c3b21bf03a1e3441010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd9486b23e065560570a5638fd7cec3e18bda18076f701ec7517b0ac531ae18d1c00be7b4cb8bd176222853d0f6057c29292e6d2d29acd6ffd1ac2afda5b6fe02	1633514177000000	1634118977000000	1697190977000000	1791798977000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfe23a05f96383dae3d0ed79106dc58ad3f04118aa8acbb0632c67dc1f708c862a5c3c6709b066eb59ed9a35d6ecee5786df873a660ca14f639defe6bf64262b2	\\x00800003aa77d4f74e10995b4b59d83e6455afd3fe6308754312dc860ca4a87944dba70be53d0569b3bdc57080132b268df4c50198a32fc2bdf7835b8330fc9ea13783346792df1defba52471977bb746b57360577591cc1a5374703bc4209968f27230b5cf3d4143186db667c55dbc18bc216549f36f9d62dfb0a4605d372b3e5a01097010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x892784cbfef37df39e9f1d09564497a21ed4073c12bd80147163f1c251a5e77ce592c6e36a67d4bf533ee16b0d5890ba69fd44fa67771898120f062445bcf304	1615983677000000	1616588477000000	1679660477000000	1774268477000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xffd74a0411da07a4a6a637bc11d1827898222d357bae53e27958c330971f5418381f2bc9f79ab84b9d942b0293426e6aebe129108d38edcb8eea905f9b217cf4	\\x00800003ad5e56b27984869a6996ecdd96590d4f40d0db5ef2e60f01d7f5fec9013bea1cdfb00e866c870e8dc2bc898704f03e6e65488d828a11ddad32d214307ac0b3f1af9419824a7cc99659f65f15e4519dee742e8df0de21161a3d41c5545e396bb18a44d66b156c597b37cbb0dd8eaa2fd8259b744a071eb4208eee4d494fa207d1010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x7772625d47472d1a97339381490a7b8458585b72dccfc07cf0a6f7308f70a0bf05711160bf980312e071c4095f19075d8177900ce367b6f118a25b3d9df67d0a	1628678177000000	1629282977000000	1692354977000000	1786962977000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x00800003bd67930072daaf52b496dff213f3ea8ab156e61c0613ae53daffd5d6ff1e4c205461fdef027109fec2522d911f98c437df586d4de5633a3b0936737ef9c8be927f643b616f98fd761e38919a05cbdf17e25f26d6823937854c67619e0ad9dc831fc84bf8ed40facb5c097fec382a17a882ae61ff0c669fa8cf77f46cae6c8c87010001	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf7629ac3d173933906ad4c5535c38aa25472d7dcd5454670d38f4a0b5b2193157246e0737e3b174c019e53041767b6495898e33034381a4d124113c386a9440f	1608729677000000	1609334477000000	1672406477000000	1767014477000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\xfe4906dd4f5a597f81f8ec106c850c12ce58b0104953ec73b9704f2306545a9a	1	0	1608125204000000	1608125205000000	1608126104000000	1608126104000000	\\xf01343cd220066fa3d2cb1a4af1551595a05c974d9d7de8ca9ff13146341b71c	\\xc92a5d38370ec708ac8bf048cdb483cb2ceabb3579a5f11b1a5068695847923da30a4d51a7a6c310dc20d022aacc1c6d380d1b6a9c2bf82161a173ab1ce97032	\\x2fe27bc6c34a3f8be71f0b5863a84ca4c3b1af10529651d3a2ed5ca774b841df3ff1e25f73d81fe92f4909b4971aa5059975027d180eadf1e11fe31cf1ec958b	\\xe410c08304ecabdcd0903a6f7d503a52b8fdddfaf4f5c50aff6fa005f82b12d3911cf157eddb06d9e46da36ab872d5f42929349f4847f1c20464b951381f8007	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"M5N79DCR37MB65VQQJN0S8W8R2G10KQCC65G418VWM5E421SS7CDK20H16NK7HGT0214ABZ63APDD6BKQAZGKAE1YQ32P9REXJFKGAR"}	f	f
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
1	contenttypes	0001_initial	2020-12-16 14:26:17.327915+01
2	auth	0001_initial	2020-12-16 14:26:17.355957+01
3	app	0001_initial	2020-12-16 14:26:17.417251+01
4	contenttypes	0002_remove_content_type_name	2020-12-16 14:26:17.438813+01
5	auth	0002_alter_permission_name_max_length	2020-12-16 14:26:17.446278+01
6	auth	0003_alter_user_email_max_length	2020-12-16 14:26:17.453699+01
7	auth	0004_alter_user_username_opts	2020-12-16 14:26:17.459151+01
8	auth	0005_alter_user_last_login_null	2020-12-16 14:26:17.466274+01
9	auth	0006_require_contenttypes_0002	2020-12-16 14:26:17.467989+01
10	auth	0007_alter_validators_add_error_messages	2020-12-16 14:26:17.474796+01
11	auth	0008_alter_user_username_max_length	2020-12-16 14:26:17.48614+01
12	auth	0009_alter_user_last_name_max_length	2020-12-16 14:26:17.492243+01
13	auth	0010_alter_group_name_max_length	2020-12-16 14:26:17.504526+01
14	auth	0011_update_proxy_permissions	2020-12-16 14:26:17.512309+01
15	auth	0012_alter_user_first_name_max_length	2020-12-16 14:26:17.520947+01
16	sessions	0001_initial	2020-12-16 14:26:17.525865+01
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
\\x2731398f4483643262ad135ab27b2a7ef1cd9e43991c93e1957137e3e3f2de20	\\x19dc336cf2e1b0180863173149866c4e420b21d7b8d49b4b36dc2c01c4556ea609973b35feb3f0c54c33b0cb3a8bcda3f82ceed0e87afc7f8a17dc6b26aa930f	1622639777000000	1629897377000000	1632316577000000
\\x29fd41de3c0745ab31d34dea63babce8b4b280ce92ed03553ec32c37f39c7014	\\x09276adbe6b92a8eab2d2375a0adad78f05e2a146547812bb066c73ad92420c67a0418f1e178d21e15c14ed841965d1bf74ba3511eb7a787a149cc3b9a2d7109	1608125177000000	1615382777000000	1617801977000000
\\xb4ae4e4935d560e9fd5207ca767b6bb9e52ecf06f2bd50bf8cdaca9191f8a290	\\x2d3f9be6db47249f7f04046202e9208dc7003d8487a82fdb4d087643dcd4d2f8f7e03d3b684fc071460f560bee41f34cd5df081b3474c4dc837e7910ebfde504	1615382477000000	1622640077000000	1625059277000000
\\xd6931de0cafa1cef7b84acb41849357936ddbbece5c341a21717d4c23f8971d5	\\xc22712488d56601e274f3509472d766f1ae1a0e1e4480951995fe90b545a46ee89b3c899edb489d2c5047bf25a48bbb8b6424964f472cca1f206a2c6b1cd9e0e	1637154377000000	1644411977000000	1646831177000000
\\xfd0b5a87ad78df056a516be43b3ba0ad8261dbca1dc59de2c614c5ce09e7abe0	\\x527f18ed666f9668833f13349317292b32367440736457778363681d932c5bf2181c72d1c289ec8b014b9fb081138bd789383439e74bc5374d07d32d02c2f00a	1629897077000000	1637154677000000	1639573877000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\xf6dab61f2fb9b7eae719497057a6cedf2d2595f8642d35b56c85e5c366c5b364	\\xb947e342d12730a7af9113d8e65a7a7b90bf9d6f6925667e296de73bc22ee767e12f6ecfe8364b4c9b269a098aac04fb534290908f2443315bcec775b4980a42	\\x5d4a0814ef70f96c1fce0681b9ce992a5c05587588ca162b17534c6fc2b5b1169a4f61cd2f96eb014c8b42f5c496f0ae47054bdfe9b773499c606f201846070a4a0cc7e758dbd7a22fd2a6cd610ba8247b842f8c2ff34d1c8b00dc0120d9fb3fde2a9982ea4b510aa92a50ae1d74a30d15149cf7e61c607756be4cb3b2616299
2	\\xfe4906dd4f5a597f81f8ec106c850c12ce58b0104953ec73b9704f2306545a9a	\\xfed912a8a29b8329d443e4a4212f32c0ae096b938648edd0c5ff151ec1b9a15fd26127314e904e4aba8fed84649a9b6cfdcdda6e493ac808fd9a1891ad078ab9	\\x1f5d69e58df43dd586d7a380c34bf0d31faaff6bee7036838e0d60df6d02183939393f3e59f4196af12928362c76ab3233f0dcaf2a7bafd7e1c25c155ecac4ad3485ec7f11f8db5145c812072da3f18882d532f35efc1a8ce710c3cca92a549a4aeffacf4e314045c717d0cb8da89b6bf095990f18c4f45432415460d58b2e00
3	\\x6c293e87ff5afa4b8d0120f1f3c00c28a7f14c06d9c0be97dafa108f61a058c3	\\x91700927537eee3d025c8517539c019cf48f363d00955a91b1112f5dc692eaa2b944454d5e493620bead61fedb02819b304ae542d5ebd304e206a32a243c145d	\\x1cc84aa7d9623e37c44bce3e36cd51fa1b095a981e9879dae3ca12633085a0b4cff34b3efe18ac49a8e784b0d867be4085d6f6c4812904c398af25f772d2f2fc9faf1b34a99ca1f4765b591433128b523d27570f55e63641e402a40da72e0b717d161ef2ba72bfe1eb888c12222c034770e2154a2d7772a1170d1e03eb239da6
5	\\xd8a208d5d9291caf7f8f113cf4a1b6b045da9700905386db400464279949f35d	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\xa6b9ef7fb741e75284d6d4d88a8a83f5a7f7aed38f04cb6e23fb4ff8f9122d10520771c69922e38731991d62551a9ffb2bd625890351c310e2d2f1e9f53982fbf85dd63215ebdff606a2d5532639163fa0d43e64e891ac772ef8ba7e5bf14ec3f00bddd230eb0512d23d3d04616bd22ab78cabaf532ec00b2be90f0658c6ae2b
6	\\xf7be0eacdb8b61f1ccdf5560692fbc055226e08a1889d1c10de9089011378b69	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x13ff28566b4bf6255fca1eaedcfd4a79129eea72dc4f5dbf394ec913b0fc6d3cb07ea53be094130069cac4d1ae6a239f53c86ef86c7e8470eb15faa6b7f138f22aade4a237825446448ef9db321496ea6e4059220f2c02d7a4c39d655be6563092d26d66c0e34a708a59691a95a282134e299159607ff1eb9bcb5e6ccee7c382
7	\\x0cc2db9ca4b9999dece15ecc1ba56e51a6563efee2064c50d2122b0cd1e17d29	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x1877854de1d4e2c705ba49047f6978aa4728a9248011e600ada2478f138da55f5ec9887e9385055d4297fdee35be1bb6a5adb1ee255fe77b7ec871742d993a096a23588c20226a5aca05a53508aa329b087ba3c840578a3ffa09f780f7930e71383d3b1556b16c6e8b5ae73ca6b8083bc11858176653904dd003b837e8093779
8	\\x6b6cf084f61be5679c9de522080611d2e7fc0d75d22512179f7afe23ffddb2b3	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x2083cf8e663339fe3eba867d00c18197b5ed54f762eadeb62899084b9563dfb8a318350916424a798ac8b732389114aa307e69d630b27bfbd1abb8797b48dccb4c37d281903950c4be6ab7c376e3e837de50c7fb91fe77ad652b695d8fa9f08ba3f09bb7ee8938e169adef02d9287d3706bc4292b2dd91c5adeba5c74e337271
9	\\x419f20e95f5a6459617e05a324a4fb9f8f362122f437447a733e1442324fa4b0	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x63cf9087ca7f40698e39d13907b6db28eb5274f64f1a8de5f5a6e814da21f9a1564ed3bc64a937c61ff78e9ef666a4af897af314b62d342bb45a2b68bf50546c3c5d2366a991afdaf056da22bde23df6929b0323d6ad638acd2d8357b79b750c194fd0661fb55f4bce6afeecafed7a86b0e1b90bcddf22fed92291f20064ec32
10	\\x8599d8b06537f61d8fba61fd7a4159064d1779e8381f8b18991a0cbe194494af	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x16eb5cf55186b07b8f4ea331d0406b9530851bd0437ea670d5a9cc683a38302399b17cce5ea39c67f21f610565fff6a88f91cd0881d6582231d14ed2f9ee6093f49abfbd82a1b6eb3b1057825e78a0e6e7a5725af7af6c01455d9c0f6f99c692ff04049955b48c8372c558e5ecb5d8f5c573c3695dd865493942de10daf5050d
11	\\x293ce705948260040b6eb4219c9bd00d4958cddf7703a99f776757433d8440f1	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x713c5bce8f20a5c9a9e3ae3b3a1ac570725ac5049510574fd20db1e58d98af68153e96d64262e6a3c2a6f02d2f3c6bd0c92e075ffe275b5791dd357eff6526cf5a67defb82027c2f205e7bfb7fed80fbf067a8ae1d09ccc198540d2d3939de1ef45c72b5eed61098d4d8711c60c071d1d3fd4a39478143494a3181d6718cab32
12	\\x13f8a60eaa805a77ec4c8d634a93b185d1f0909012003c28c8c0596701c02545	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x7af301200fec0b458f5785287e8f08a7057a98432005b236a92b8769ec0f6aff081f0d6c29c8b2ffdf202394f0f5c810813ddebb77f4f0b3f8d1eea2f2e64ed44f5a4aecb5e644cd2afc77ae3bc21a709371f5dc9a527d9614e39baf588796a56972e47b26de4914b2e2a038c28f9dc72b83e41661b06e79089468a96da8d380
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x2fe27bc6c34a3f8be71f0b5863a84ca4c3b1af10529651d3a2ed5ca774b841df3ff1e25f73d81fe92f4909b4971aa5059975027d180eadf1e11fe31cf1ec958b	\\xa16a74b59819e8b31777bcaa0ca388c0a0104eec618b02051be50ae20839c9d8d9881109ab33c61a0082452fe61aacd69973babf09a9c1f5c62b270eec9f382b	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.351-02M8V4ESTK3CG	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383132363130343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383132363130343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22355a48375148503339385a525153525a31444336374132434d4b31563342524741414235334d5832584e4541455835523837464b5a5746324258535847375a39355834474b44345133414a474236424e3039594847334e44593747485a52525759375039423252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30324d3856344553544b334347222c2274696d657374616d70223a7b22745f6d73223a313630383132353230343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383132383830343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4b5732504b56515039445a534257474558375937415033424556304d59594e5a57433857513945454432324537345047483530227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225930394d374b393230314b464d46394350364a415935414842354430424a424d56374258583335395a5739483852543150574530222c226e6f6e6365223a2245473834353437435951344e584151443857304b5135504a31595a314153354a4336333930574146443531485333395841464330227d	\\xc92a5d38370ec708ac8bf048cdb483cb2ceabb3579a5f11b1a5068695847923da30a4d51a7a6c310dc20d022aacc1c6d380d1b6a9c2bf82161a173ab1ce97032	1608125204000000	1608128804000000	1608126104000000	t	f	taler://fulfillment-success/thank+you	
2	1	2020.351-01M1VHQSPG7E6	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383132363132323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383132363132323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22355a48375148503339385a525153525a31444336374132434d4b31563342524741414235334d5832584e4541455835523837464b5a5746324258535847375a39355834474b44345133414a474236424e3039594847334e44593747485a52525759375039423252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30314d31564851535047374536222c2274696d657374616d70223a7b22745f6d73223a313630383132353232323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383132383832323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4b5732504b56515039445a534257474558375937415033424556304d59594e5a57433857513945454432324537345047483530227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225930394d374b393230314b464d46394350364a415935414842354430424a424d56374258583335395a5739483852543150574530222c226e6f6e6365223a225930594a323731315342395833354132434a4b5a524d59594639413254345334503350525344454239444e383736573933435930227d	\\x5cd225532e80661571484c73c1bedb659830f27a13a864e95a69b2f385ab13a61d59dfd5a7bd5830038010ac14f9114f818e1271ed24d53fe24d4bf38fad1e3e	1608125222000000	1608128822000000	1608126122000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1608125205000000	\\xfe4906dd4f5a597f81f8ec106c850c12ce58b0104953ec73b9704f2306545a9a	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	2	\\x03470a76b3a26a38b1c26b759f292ed284f008549fe65b860ec786e74a3c79f3661027ad8c11a3cc4afb48050545e743e92137518be0c892a43c8a19532a0d00	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x2731398f4483643262ad135ab27b2a7ef1cd9e43991c93e1957137e3e3f2de20	1622639777000000	1629897377000000	1632316577000000	\\x19dc336cf2e1b0180863173149866c4e420b21d7b8d49b4b36dc2c01c4556ea609973b35feb3f0c54c33b0cb3a8bcda3f82ceed0e87afc7f8a17dc6b26aa930f
2	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\x29fd41de3c0745ab31d34dea63babce8b4b280ce92ed03553ec32c37f39c7014	1608125177000000	1615382777000000	1617801977000000	\\x09276adbe6b92a8eab2d2375a0adad78f05e2a146547812bb066c73ad92420c67a0418f1e178d21e15c14ed841965d1bf74ba3511eb7a787a149cc3b9a2d7109
3	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xb4ae4e4935d560e9fd5207ca767b6bb9e52ecf06f2bd50bf8cdaca9191f8a290	1615382477000000	1622640077000000	1625059277000000	\\x2d3f9be6db47249f7f04046202e9208dc7003d8487a82fdb4d087643dcd4d2f8f7e03d3b684fc071460f560bee41f34cd5df081b3474c4dc837e7910ebfde504
4	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xd6931de0cafa1cef7b84acb41849357936ddbbece5c341a21717d4c23f8971d5	1637154377000000	1644411977000000	1646831177000000	\\xc22712488d56601e274f3509472d766f1ae1a0e1e4480951995fe90b545a46ee89b3c899edb489d2c5047bf25a48bbb8b6424964f472cca1f206a2c6b1cd9e0e
5	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xfd0b5a87ad78df056a516be43b3ba0ad8261dbca1dc59de2c614c5ce09e7abe0	1629897077000000	1637154677000000	1639573877000000	\\x527f18ed666f9668833f13349317292b32367440736457778363681d932c5bf2181c72d1c289ec8b014b9fb081138bd789383439e74bc5374d07d32d02c2f00a
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xacf82b4f77b25bfcaf90774fe3aac35bb60a7bd5ff188e5d2e7344271c96844a	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\x565dfd1b65a20e31982b28b41eb7cca03414eeb185d5d3d74cdc1c866aa7dd52a1b28bea436faa112f02769efc7a77294647a3bbf4996ea2c97a22e30c730e04
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xf01343cd220066fa3d2cb1a4af1551595a05c974d9d7de8ca9ff13146341b71c	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xe1ae7aa4e05b630af8a36887f923fa6a8c09b415fd36ba67a8a4833d0e79a943	1
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
2	1	2020.351-01M1VHQSPG7E6	\\x2dda3b62a769b732ca21fb660c88eba4	\\xfc227080bc79c59776f22ed34abb72176fca74549c82b3d7ad28c47d39772b5ed207f0732496f01ef36f38f7f437cd3043bc1e17f28ea44db518ea5c69ce65b0	1608128822000000	1608125222000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383132363132323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383132363132323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22355a48375148503339385a525153525a31444336374132434d4b31563342524741414235334d5832584e4541455835523837464b5a5746324258535847375a39355834474b44345133414a474236424e3039594847334e44593747485a52525759375039423252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30314d31564851535047374536222c2274696d657374616d70223a7b22745f6d73223a313630383132353232323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383132383832323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4b5732504b56515039445a534257474558375937415033424556304d59594e5a57433857513945454432324537345047483530227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225930394d374b393230314b464d46394350364a415935414842354430424a424d56374258583335395a5739483852543150574530227d
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
1	\\xf6dab61f2fb9b7eae719497057a6cedf2d2595f8642d35b56c85e5c366c5b364	\\x5176553fe638d99c28bf37d50b6de5c0f472bf4c4bacb47b8fa99ba4c66f0169fd48409da2ef7c9e0be8159d620e5cc6153d3968d08d9bf0bd54d09f9a5ffd00	\\xd94a6ad1b74f2266c8f46fd8414f91f36b3a07ed267a5bc775a3b645fddc2789	2	0	1608125202000000	\\x6d02eb239946cf8badf99ac3c1fb7589dda8081a57165642bf195a5e2ea1bd2f789fa3d4c5e20f5d9e4e5624c36e353834fac495572d73685060439d9848b85f
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
2	\\xd8a208d5d9291caf7f8f113cf4a1b6b045da9700905386db400464279949f35d	\\xce3c49d2c4849e0de2738a7a908d9708280ac02af947f935efde5dace37ec3b2a7e5f17286cb5e9c11045a6321d7ae4388619bd7a8df66fc0436bf9cdb78be0e	\\xc56236b3511a15fd2c1658225d352bb27f02497e35e20a02dfd972b110050dc3	0	10000000	1608730015000000	\\x30fcc38bac0544dfc6e8dee3896f627ed8ef63362901f6473091dc709ff7655cecdcc02635c52342c64fa2a83a2c4dfa2f225eb197cded39454d8034a4869a2b
4	\\x0cc2db9ca4b9999dece15ecc1ba56e51a6563efee2064c50d2122b0cd1e17d29	\\x79f2d2656ea5a331762eea140a214268408723ff4ceadf5ef8754d245bfd03337334b45ce61a57b624f0cf28d6d1bf4552b90b493250d0f03e5a37536f7b150a	\\x80ac4c9aeb4010202ca0d46745bf4d45ac2d89a5a154e79db2cf8ceba4b61135	0	10000000	1608730015000000	\\x367b388ba3a84bd7f8ac3d2f8f01a688c74369ebb324efbb9378b9ba591a590a080d47692841bf7490c5144eb8d696599f788886c67325dc66f4a63a9d19375e
5	\\x6b6cf084f61be5679c9de522080611d2e7fc0d75d22512179f7afe23ffddb2b3	\\xf03b3650c378d3a0304cb24c6fbc4d7003612852afb87d24d2373d72fb631298f2c52dd483c3f5ab3dffa8272df57a19aa9b35ecb8c9680daa093c86b058030f	\\x9e4d536f8cad0b4d81c87579e7e0a82dc5826be26a34901a0632207eaac453cf	0	10000000	1608730015000000	\\x48b211a61e359a41fadfef70de5bfd2f52ed360135b491bfdeacaad4ad77fd4eea9a418fd63bb1269bd438a983f7b1d351adeca83cff4a072184b625993b5c55
6	\\x419f20e95f5a6459617e05a324a4fb9f8f362122f437447a733e1442324fa4b0	\\xe98c0f8844648f96222a31e1bfc4a69d36050c4ba3f104c603955597809f6550b83a258928def08342466442050c16aa022d2236f7f9234213f9440fe8045507	\\x181336b9df80593fa0fba83cece498d28325e8cdf2db890b087860a978523042	0	10000000	1608730015000000	\\x9ce912f108a73e95c9812063a9a77a380de64035afda18a630a0bc44fe641d3a8df87249ab2fc6f5048ccd0398dee8b8995fe3f3e33eb58c575ccdc271fecfef
7	\\x8599d8b06537f61d8fba61fd7a4159064d1779e8381f8b18991a0cbe194494af	\\x2f9d07fd300b51865575282e838a9a7c9d46305b76e91cb3ff73014c29d516730e52f5404c99f710448b840761fc5285d514d5959c5f5844efd106dec0292608	\\x4e7c09a407afadc8b55a74fc0f02b0187ef1029922cb13d0c3c755a79ad2b19d	0	10000000	1608730016000000	\\x239a37918e69cc6f14ac913fa686c653eb665945fa50864f8fa844ba14071e71359f42b29caabb813ee4d4a03014a19c5e5b9ab9f0c7f8ca06bd17fc4fc5e426
8	\\x293ce705948260040b6eb4219c9bd00d4958cddf7703a99f776757433d8440f1	\\x6014c343de72bf68c33b883cb993aa7b12ff8218e9bc30b7a695b60f41b1e4ac458a5839975e385bf7207ceef86c31d584da33eca8974d7842dcdda7d2709e02	\\x509a540106f252d156682bc0b8258832d31783da4e675162313c4fc26de1e949	0	10000000	1608730016000000	\\xed121b0d7a4b9598224898006851241c1c23528f7d2b2e8aad42866820ea2ed779a51268563c86c1712457c24aa4dc2fa5edc6854bf76f25252e1f9e90f3acd3
9	\\x13f8a60eaa805a77ec4c8d634a93b185d1f0909012003c28c8c0596701c02545	\\x4d5a92f7c44edcf44216988deb64dae477557506b0853c045b5fdb6480082c8efacd0238241eebc44ac981bd47853e4a1605ea594c158732aecca53ae2e5a602	\\xbaa215e38287d81c592a1416cdf6ac298d0870d3d4cdf15b1d1cf94ccb664894	0	10000000	1608730018000000	\\xa34990ae8c2f6b5bc8eaf1d3fa5240a9220616a1d74712327500bfe3a860bf52dbbad4a20c29139baf430e0673dc2ff2f2b4acdeaf56bd692ecc8cc5236af150
3	\\xf7be0eacdb8b61f1ccdf5560692fbc055226e08a1889d1c10de9089011378b69	\\x950e474d1bf244f2d5fc7961a5317744c95b56888d122c12e90beec7fbe986f424056f0768cad291e6f19f72ef68d7f65f126c9d0a474938130fa581c06ba805	\\xd08ed6cc1c9f1279ffade799f784b61e9475fd1d1c24d8fd6bdee6f34695ae9d	0	10000000	1608730015000000	\\x7f7b159722e28da8a18481b3c2c3b6c8e946c33f9179401396ccd5cd3943553318dadbf5dff339cf2a25e03873593f6e816eb70a2af8e3a90f410f5a9b5b5428
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	\\x6c293e87ff5afa4b8d0120f1f3c00c28a7f14c06d9c0be97dafa108f61a058c3	\\x66bc3887ea6769efc1cf1e7bb720cafbb51aa41089d877b2d601eec9ea1dfb78a66cbfa47a3e97e31a09cfed6e444b20a47513cbb3d256dc514a45a0fd1cdd06	5	0	0
2	\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	\\x6c293e87ff5afa4b8d0120f1f3c00c28a7f14c06d9c0be97dafa108f61a058c3	\\x3944032c9b9df527e7780fca338de31c6bf27d8bd1e333910397e41fc5872f1e2333165208a7cfff2889d108c03513c3dbb988c8fceffcdbd4b4673b65461009	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	0	\\x8fd0cf3b996a85c162bc57cdaa93c655c2c8b85ecd089911bdab25e5ec33b19ed4835dcbcb9ce22e7136bf1b85b7fbbcb8c527c1c59a6680db45037053b2ee01	\\x7127d71d961e4a72ab6f8c8c43e201662b94d8ed6e9f56fdedf1a74d4bcd0d4767fc1ea95a6144e66e900c2ea2275679e6c624e7c2847f23b41db53de05029d1	\\x767872239fa756252f4c781ae97774277a3b61a6c564e90a6643f2e9a198172351f22686cf6b6afa45c3f6185071aa4d02940cb3897be3a9ad7f2882697a960b876a7fe5b961481f9a39be3d0583301264204b50617c9215857ebde0425ee6e5dee82b5b55d1c8cffc82cdf9c1f1b276935748fbaf2e299e2a384db1ae1ff345	\\x65f1f993c388f1a9b0db18a94da38533b383dea915046d2eefc0eb734626df1168f69c940ad8aee481c93a8fe067dfa9a4ed8a7c0b5304bd9286f810cab06140	\\x51e4cbd2d810cd374bed95cb5fd396f0d0e46411e51104719867db6ab0e786f3339b67cfd1a64dcfe3c1bef99603bbe4d526671be86c04cc4ca2075f319e30a009921d119789721033ba33360cba8431e15c9ec3ac2f55948744fc7852c3c92f4d4fea6f18b3a2ad331b6757c9f352661c8f9ccbeb9a3ac3649d7f21f20383d9
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	1	\\x1a53a50e882805e193543ebb284857306e551233032fcafad61a7190f13c00a42322ef3b5f3e52d25a10c5d926723d55df192527f627f3d2281d71473fe0420e	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x55cf4e4ba49128db5fd03a43a49d3414fe565be46b7f6a3315d0d22448420fe8e2288fb642a8680465456f0768c88da4de6c494e87cfab36ec0190075f638c70b8ebff3e7f4805102a5305744eb7cc31f4a9c6213b1d0acad96b095801975ac0394ecf75e0a18c970614bdababdca7330dd63cb32fa166e6726a28887d67b390	\\x30fcc38bac0544dfc6e8dee3896f627ed8ef63362901f6473091dc709ff7655cecdcc02635c52342c64fa2a83a2c4dfa2f225eb197cded39454d8034a4869a2b	\\x10319204704f3d0ea6f6f4edea745216a96bc2384fcd6108075f51c4d8c920e8df3d59b014d0e3ea266d9c35f66fd4e3286258505cadff9021d89da0e70a1d44bb23a70b4043c972b6378db21f2ea0811adb47b96f9cc1843c7aa165768b6c4553a34434a5f0b4e791da184c1b2a133f9bd8b35fec52b32074caffcb6621ea05
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	2	\\x8e787a8f6472dfba8f2b059f16faaa479f949533507fff3a25280272da56432e2acf4d7cd34921a407a21b9d406c64491ab89e341409f2085ecb08f2bf2e470c	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x74602154e06d8aadbca2c662e40cffbf665e44bbb10578532a21d53a31b216757591a88f95987b9aa1a55c84348b84e077f1a2380e034cac218b0bf46924711261d1c9832ebc1744e7486ed716c76a4ba0582f756b277dc447b78f72cc271ff5522fb0cc763186409aa7c6bf473f463518480c9971a66835d0abbbd9c8c28ae4	\\x9ce912f108a73e95c9812063a9a77a380de64035afda18a630a0bc44fe641d3a8df87249ab2fc6f5048ccd0398dee8b8995fe3f3e33eb58c575ccdc271fecfef	\\x53f9cc6873690690f50bbf2e587574e8ddab49e26c05eeaf0e88929feaab03e5e768f07419202c15bb7cd5fb061d5b32605ddf77c61c306a50d6296e25a983863a2cd83335f3a1ab7ce9edfaa3d907b2c28df335a5b83b59db260cc52a343fb2d3bfbe08a74d691b6307d31653a6101f3057a6c108f514e485be2019f3c3f972
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	3	\\x7e205d87ebf33911d6b79c01212c98c4d7211707868e96f12581c58a9d2e6021e67e83814847b69166482fbce10bcb16734db55ec6828d798d1281846e14bb01	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x9b7806060e625a2280b0a18505b208f8ccc111f605d96ba3cb65d7fdb90d4ff1c9974703bdce15b4340abd995565bf8ff6376a1fb58e2f661b68bfedb981f1298eff142e37550461ba9325e2f240dddc71a8e466d44417e484b7f486a11c855aa2a8fd2e2e519ca495df80704a361e6c3a934b6d030f237927214120b312982a	\\x239a37918e69cc6f14ac913fa686c653eb665945fa50864f8fa844ba14071e71359f42b29caabb813ee4d4a03014a19c5e5b9ab9f0c7f8ca06bd17fc4fc5e426	\\x67c09df93714ed334a077e00faa947f7659217272ed793d1bcd052060e8105302b80235dc2a3330f163531f15e30eb799e8de0fe1d0e0715f89d39a3c916b339526ff482d321f2ffd66f49a7889db7dbc1a528fd1f2a4bb352a33b90184bad984f4ef3500aa1082cee02dd31e7190ea880dc20a6403df0b053cebe68223ccb84
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	4	\\xb7ed4760d1bffdeb7dbe26bc50179ce5006e6749b7acb049d7d0aa583d17a0f6a5cdd9328f49eeaa786928ec4fc9cfd4ed398b12f156b8f37ff6361c3fd73a0b	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x63560d4caf1dc8c2cdae782e809a1f6887b93e55eafbda8f9d9a1b8743a6308d375540b273cd49a9bfdac633a297fa3b31ec13cd4f112bcc0c5d2cc1c55ec07445256125ab1f2a57125230ea2276ebe61ef79722b20835722a5e37d3144a02f0e1541bc048685e0adaea9cb61425f7744c21891345c52c1ebed1a94dab1272c7	\\xed121b0d7a4b9598224898006851241c1c23528f7d2b2e8aad42866820ea2ed779a51268563c86c1712457c24aa4dc2fa5edc6854bf76f25252e1f9e90f3acd3	\\xb9698060d20860e0129e832be7db9904bbc1c29ef31e78a6bf290fb828de5bcfba4a3949729d55917fda164efb6dfb0b855ab69ea602bece576347ca7710df840a7ecaa47818df0ff3f5c52d3c937225db2df79aebe888ed74fc62be388e3aceab4671b064c1e009bf45e5441d4b6d752e76bf51264e52762ad9d08ceeec9e3d
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	5	\\x770c4f2950a17f10c8d3ecf6d501b6e6773931f33d2740e509353bf68d6a509aa4138a1f7abbf8cfcdad94e107072aaa58eea5e18960f63939f32a151025ab0c	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x47398d707005f14ef6ec2f292de3a603ebe5c2a3f145b9914a16d4a3d8537b0bbc3d60aac95107ee97a1c8c0600832380e9e04d5add9b376699c1d9f6103a715e4f2c0b785860aa7dfc0fdaa9d4c30f54e92d2b4f7695128ddad397ceea0ad7d59e703f7b6132de03790d3eda86df3980c2bdb45524e46d36c3add95c5c84e05	\\x7f7b159722e28da8a18481b3c2c3b6c8e946c33f9179401396ccd5cd3943553318dadbf5dff339cf2a25e03873593f6e816eb70a2af8e3a90f410f5a9b5b5428	\\x6cd3a8219f45fce819c6a8211b8e6e1fa89ac9ef9019fdf0e1abe81a2fe43191b931f8450f3a64371f4851b7e7082564f2fbeafd07ef766bea2350b9204ab67c0de441a24ee02ac8b41a1c9d88824cce6167e84d335a7af495c3eeaa8b7132920e08a45b52ac391d999a01ed2077ca97cbd7255a816a3cc2a45b654bd0f62101
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	6	\\xb9e940374ad1e70dc7f67ac7856f4f7ffde5d57c2d31ceb4f90f8c5b362f77504fe2cb6155494c5cf4f09c727a12697c4923444e4a5a65288338b777d01dc108	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x592990d31bfa9536cc20c6b966fd4150748f949364370f3d8f2d295ca484ec058afc29b42b1330f0f06b9c976bdb7dc88ae9401e64b695217c8a3c9c3af82e247cfa1637ac0b526da180a95eb60ff2c83fe93225d004cb5a520b941a4636fd80951629a08efc85e556d7374243deec6b03f0d128a48c14c483f2d3361ce5c26c	\\x367b388ba3a84bd7f8ac3d2f8f01a688c74369ebb324efbb9378b9ba591a590a080d47692841bf7490c5144eb8d696599f788886c67325dc66f4a63a9d19375e	\\x28ac7858450066941d5203ac46dcbadff4b76ee7ed3d7011840c18cdf96f5c11f3df586e1071388bda6442faf1708f1d172df8dafb59949a2d775c3bd43eff020e7ac646f86479322afb7ceb52e51d5d0c7985bac997dec165781db2a3602c6aae0c7ad21e13bf2ec3256503072fa99f8d165407357467dfd20c73dfcc53148e
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	7	\\x9db3544dde6d77c016611f16927e50fcecf8c20952be56db8ccd188d359c32538d9778ada3d8c0525fc798af93a58f19d70c84d79c09edc4364aff4c66b71109	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x0f43e14281a3a26ce36de27cf6cb46c2581a29364ccd25f9709f94d027e21229201b64fc75baad4a129d7c1ec19e9c896c42afc517851e7e196e1b5fee7af8201c2801d63e0043763a77ebb2eea02c3f1245a1501aa8ec747b5023793c83cb6d077cc9447b4531b3ae12d82a9a46f43c7d5b106061d99d95f1f741f40dddf5b0	\\xa34990ae8c2f6b5bc8eaf1d3fa5240a9220616a1d74712327500bfe3a860bf52dbbad4a20c29139baf430e0673dc2ff2f2b4acdeaf56bd692ecc8cc5236af150	\\x069f8874d79e7f1b360e33558b013953646c3119ececd15965768977bb3236b7c210363c9fc2d46a1af7c74392fd3fbbeca96e74bd9b19adddc02a74257b240d0bac9ed4d2f7ad78444d8ac676453d383fb51426585bc13f6b911aa9ff3463e1492bb213a8657f22c143a2b32486ce8c43d77ed6f08c5357b7093bde12f48d40
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	8	\\x6a80087d2475fd8ad1cde7c9e1e82a5c6e5ab47280b8c620bf3115967e57d7df0dc1d5dfda1001fb68d9d22f4634dbb2e0e0682cbe8b6a2c76003627860c9002	\\xffd78df00fdcd6722cd64a5d83f152ee531ceb078676a9aa34fd4e483a7eba3cd0ad02c3b5266bff622f28ee759a34339100343e6993b1bce830f4f6d60a2685	\\x9b8c4183b1292dd3a06dbc5fd46f8401dd5a35956581283eaec199460e2c66278e1df030ce56980147e5c0dfe0d9f472f8fd21d30c4c8de3c6e723ecc7a375ed10fe142d4ae59d5aebe7461aef12662303a9a96e2759f2db0a535076180a5d54153844f3fcb16a0333d6e3b11bd38b9179154ec1f5876fcfdca4e21f2f1326ba	\\x48b211a61e359a41fadfef70de5bfd2f52ed360135b491bfdeacaad4ad77fd4eea9a418fd63bb1269bd438a983f7b1d351adeca83cff4a072184b625993b5c55	\\x4dcca95da6914ae9724b8c64fa00ed2a95a4f847a00a9cee53113a6303c2e83993e123cabe6a8f02a0425d152adeb13c3779a01bdb807fdb497b27a4ca1b64369dfa1826403e280c85eef86053fe7e89b0d1e25df6361770e4c07d31e8d33cefeeaca09c2f18df31d51b69143a9d7e7b37520b965fdf6254085ef7fd100f6b1c
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	9	\\x59175e56e5fd4c24d583f783fc1e03d407dff73feee92206c3252f0f58deb2c8efbc1c2ff625a9d66c3212faaa36b2bc26c52202bf4098965f8f941fb5a7ae0f	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x62cbe5f45f415c63568e7d0b33842e4d714542136c4451ca20c313c8272567dbe083788020149d55a895a2784535fa93d0e63f71d205178da7e3fd06c85f5807b858473fef3181c799278d85330a990d4b13fcd149602711d4423c7f186d89f4c9a235c41f7d7639d69a4f08f0f9318afc36665ce4164219a74b5c3c444b79ef	\\xa60b5058458b55c550dd0c677405131069cfddcf551131795125403a38335edaf249c6450274383c8645c5f83d9e3f6098441853d7deb98ddadca1dfd8bc3e2c	\\x96332c9a11cdc81357ffe5cfef7b24821be8e035fc489b77d4e67433e34cbd931fb2b21d6673e5a3124fc9183b6551490a366f971929fdecda1f19c80ad963425701d2bc3cf7ad026ac42ac45d8a3e1af9aaeddd51f847fd94f997100ba578408d478f07b7094bfc4d018dc91c481e0bc877495cdd3a93c126fa35c8339da3fa
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	10	\\xc4510c35530114437a61af3a7c1dd1efeab22404c55b9990d3a8b489daf2a15c203423b78adaf1b01dd9791bc929a9064e56a00a1a6d1f8d186f5fce4d85d506	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x434fac14ff3f26610759f3cc795a007809a89c579ef6b4853554ce45534ee22f8f713b1d0820731836ddd41a7aad58ae7c9f070718c26e26c6fb9d6e972e3b7984a8edc6dc82763fe5afd5eb73c7a6e21e8a3328d4ae901ed7602b9861e2f8a07f90fb902d815965c05808d50c6e92bd037cc7caa10ad312d428d01a3a3ae082	\\xe1346cebb62b3c1bb3627ee26fd85db2580231a844a0151ce9b4e087f1ba4d4f9fe253392ec67f50e8db091fdf86b46e9428b6b744d2f94fd40301da6d104886	\\x8b343c71fec2eae9f55b0d17d7db7877cf5acf9a134260151946f9f149704e95ef1c6038870d083c4fff8e5ca46d6fa99459fe1d391dfade419c2c3f25f9a78e9320017849dd46c40717f7e07bd7092d9b8328d1e6a3822d933a85e0f3bca11ae42bed40c18a91cbd8c8031f1f14099f1dc5814e0b9d259136343a832ce7100d
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	11	\\xc1d6228617e4b7e3faf743e467fd41dee93858f989100453f04c0504ac662803b1ddc01b114aa6148b43611e44efa83093c1c36290ac7d1a4acc182302853808	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x470afb18977485e3714757119b137f131d8a95b6e15c1cdf095c674ad9f0bdb8b0d3ce1872eda33d4880ad04b2455e89498e62118d04fb5bf4f624e01e5d8d78835f4359606107a1b88c1f0841202dc2802c9c4fe7f8cea1054a2bf76a90b59e70f923d55317a66c7fe9899b10c5fc5f8f19a56fb2389403c8cd088aa91b202b	\\x9042d6c26ed263143c2aeff92b7359aa71dc322da3d533b181db337554f6b64b556b0c5a013ee135b6e0c32e34f834ac90fab4e6fbe52a91a5becbd7ee974993	\\x5e319bae60cb7fbd1124220b8314bd1aa168c20733bd02aa0fffa6a0ede78711ca3749eb16a588421027013a9d02bce357c3ebfa8a00c45bdb11c121e5baebf219fa36fa1c884b59d611665824144737baebb366054857b4da9e280dac10d021eff2c10ca9de0d662f02d352f2a937feef2d9a083b1a5a6e05b7dab4eac1111d
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	0	\\xefd4d76dce9c0d0cbc0a38eb64ed4d8bdc1fb807315cbccfdeeed0c63e3ffcc04055381efec6fcde7a8a7280f971ab45f8b50108029db949c7e9a50558cde00f	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x944a523478d2860ca6102553ecd1027cfe3e8548cd84a6a831ad71462628c7acdf31521bede3df2b857645de0b8a0eeb13ba58890fdc46fbec11acc2ce279704b075b2b0a111db7824bd6a4329868b76c675a1e3a9ddabef3c63c1b2ff0e31fa1b34bc86c729a41ef9d0a8c2471983c9f01c423524319d961ac6918a0818b85c	\\xc1253a2a64444d0027fa96a1880c9a2ff489318c6160004e8fb7be545f62f9951795b8485ec56e831bb62460f49e2b20e3db5a8dd8c0e3485cf329b7066acc74	\\x018c96e4e7440d2278cb064b6272acc758acc95a5cc4756fb9bae25edbd2060abc7da1f62137b707d462a194443c2523c9279e199574595b6938a79982c630fec158c5a3bb5a7bb22aafde471f89af90764859f0917362acc950ab8decdbe48848161f12bdd471c8d525987e14db381d0914de83b40876f85e8018aa4681293a
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	1	\\xabd743c8afcbd7d402fbc197f52c7c8226036932fdca26a733b8136f361907eff063a8fe380055b2298b2ec5218892ca4e8872dab66e5d69b0a4cc506b962305	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x1e01b5ecd91e2a8a38478ed7728a0babde56d88473720fc76770ea128ccf14d55cb71bd7818ea7ec9e21f0b02c6b26662f0a53ba702f648349922689555cc85d992ece317d0fc2a8f95a93661aa46580aca88ce56d36a37071f0cda105d2a369ff5e956714d8ef5dd39b1b05c808127c6a9090b7573396b5d769afed2b1ff0ce	\\x73067f8b32ef5a80554aab9afbf6e7756f9214e2e7e75651cbd6b56c60417bbaaec5543b9dd67369fc942a260bf59dc9f0434f393ae8f7e07946990d683bdb77	\\x8f155425d9b98dfb5f78852c34a6d6bc1606fa07e863568607c53265ecad3d9f95c817db9a4e7348dbec5b74c0a6c260a9215b59dcde4ef7ab7957670b9aa0b4bbc7b9492bdd05994e91f34cde7b4caaf14564564e7b47ae682fcd82e93e7a97250ec55401a2e853864f59d345471e413758f5ab22f75019c5aa3995e5425fb7
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	2	\\x5c96aee7f977f1e87500c1ecad64839bc32b82cbd8e828b9d6a29ccde654dfd6cdf8fadd32ab297b9fa6abac68d10723edb97bcb7004d63690cdf500d5d19f06	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x4a17ab09d8f57473bc0d7f40b352c7d4926cc20988e010d06f2e8c9acfa9c5ef8b052e7d552412a88ce54e665acfac6e2e720c5d1a2af36360e280f013c039d6869d087af6ccb87e8df23939136369090af749665a960500859de0bdb7e9db282fffe8607e9d11f8552385d59c10c3c228dfc08a1d2d5dc1e51a4abea48923f5	\\x365f823409d9b6e44db26c66618d6ff8803df99580604b3f56332390495bd612bd7f8a19b54bdfd08bce74f2d2058355eabcdc884748f026df67597482823c9a	\\x646aef9b843eb7a764bec021fead456bc1685728c1f72361e01331a17bb7b983a6ae304f8aec38ee6a0f39a64783db83a104aeac102ab5b1f88677191936595d7d16cb2b2601a7ea32e71a3f276b0e9596f88c26596595c28096ae4c4555edb4624cac20f8432d08fd82b608ec7adeef3d88424de205c8afb8ec0e9032367380
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	3	\\xf726a86ecaad4b6a013f85bace29d3abd80a910a34bf919f048f6f313c9e992d73b019258669e0bbf3699d99ae4ea9617df1f5a34e3673bd4f757d39aaeb4b05	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x1b718566f5e2f48989d21a0a956cd1c7059a95fcd8f8743a68ada3ad8c7cc27f7d4ec5413ed20f4f2f43eb84c8b83016700ee39161b459b8f93d9c38f820f04c7a27b443b534ec81e9196b3f62bc53984dea2751d77e78b695578f83afca95ba9493747a0bc3660fcd05b5fdc88293826ab9d5935cbce38c056cf4bc272a5943	\\x3c74dcae58ed75fa32713598ed3bbaf7fac65531d991315287f8932d3924326328e7b9c0e1938076da4d933e54c5be244b6025e91dcd3249f0c4771e909fda39	\\x74d8c21893adc14640f0e20d76e865971fab6a9535fc984f7e7697ad3062e22cdefdb4979e478c5e9797f562b93e885b9da5b2cb2eb3410db58f6f0646ccc4235877bcc4e255d7575862f3d35cdf6bed7011b5506ab9822e34e8bb4e47c4c9cc6fc6dd0402cf35c7921cea83a69a3c71cdac939ca7d2c96169fba9de4b698e60
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	4	\\xe2f7c4bda1e56f40e0cc9b182ae4337c616689e4dd9f78b87553d47a66e3f7d6fd13318aa54d33c0ca9b2d2882b0d256729a5cdc05d7bf43b26c4baabb29d306	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x65343f0577c6a5aedc583b50a164b0589f7ccda963c2c033c4b8b1249197cd65c9b0aff7b7f7f226daaa9e63ff103e8aefef70bc98e30d9d6b45b1d5228ff11251f37b64d5c9742eba016c47e62731e58e9d40e1ec47f9091ce368f83100ba532f7689ea0cf5e6a27f87f3dda16ff0cd3921f6fae998dbe4aa40a873045cfcfd	\\x68806887f4d6106a4d4eb963dfe28397c2e021f4086fdd1fe5a3a77bdf686052eac0ad6bc99f6a0dfdeb6b77c1a7b4be505515126d99e9dd8124cce3f72eb801	\\x345e8fdf556d63b6694f4b03e0b56b4a9bc495280856ca47fb6569f63bac72f21f3f106fa2b594e8dbc9f2803a1909979af75e722861a257c1df034b520d8753dd407c2d45069025b8a066d06ab4a818980080e5bd89e51c3901b376bd0cba9a98b7ada4da196844b083bde594321b7532ba90dbc26376e6fdd025d6f52c2615
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	5	\\x0705816186cd260760ca053bd74ae00fb2f3e50fab0c816023142590697b96b97c0d9e3d67c4735567fe96fcc421962b3a23c1e3f6f9c84caa5c23a34a155005	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x7bd80b9bd9f26c2c998840852f7bde522609743e3d20565d3b6781b87259fff52f7091378f09b741b36c0be2ce6a26d371896d9150fc59fb46f5020b6e9c878ba3805c66cca79e7998871dcfb7cf315a03fb4c7d50a1d9d18709a263c89ed0641b8844b419e853c6e63a8474c896ad937b6aac46015eb368a6eab8328888be4f	\\x67034dd7b7b12cc6580965ac3dd33bb440bd290709efcfed65aedda92d40a8721addb8981ec40a00fb634342094a6aeccfd83d3d877213320f3e9f33221f5620	\\x37c3f8c19b73639401ee677e1b41f9ed681a9365029a09173fef6697c5f879612f353eaf9912e8ab25da956d8f3d723cc5f00aa0f9891b835bc42c04f92204473f5976c5b2e91dfe0461d85138f38434e285a57bf9939654607006024be346872127219f33c703b11788eee2ff64e9215131d429e55a323cb0de9a8dc841a960
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	6	\\xb4ceb60507e44b98a7e866d9175b0ed2fc22355c25133ec11b322d38ea48432fd705f10c1dfcba918d3071020f198b0537bf7dfb6a67c1e8acd490f1079ef203	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x2232e089617a34f3892b5e91a90388ec99b9417f184102c47c84fe0be79783ff0ebba9e6f3d11791f89a333332d2e485c5325807738b55efd2b57036d5784c4546f0ab1682fcd1d8ff9d6b7685c8c2cb2e9380ec0194de16014c0c442ee86baf121e3c1a732457e0702322b83f87dcecfd7bfa98a7d4440b5a374900194515ad	\\x79bb128e38ca2907ba4e271cb26cd3db165ee190975cc8d33b3e7f5afa06c7c5dec75fcd63d54589e097f7564fb904403a1e32c2dfed96a1856c85cc3cddbdc4	\\x072fff902de389bd0007e927f8a98252cdbcdd936ae4a48ecb4c3dc68ff6d818187d7ee723a695529b0ba9607cfa0c7e21941bf980a61a3aa2736c80a36db0c347369ed9b57c2c97ee99de5ac59ea619336d9843e9f16ab89d96c93973a1a8f6da35f26b0523b2c96e21df8f14da7ae4e167e6fb9e9954393f03becc3f24164e
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	7	\\xcfb05cadd6d90b78e691a03a3e0e38bec565c8ed2788084a39a2bdc6d36c49c90c8315e801202e05a9c8b85c0a34d99ffe2b853f1c3a9c48aed66dfa6aec7808	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x64b143f6eaca59bb78c37bea7c52779d85e9a468fb33a02cfd06aebdfc99aee9f4ea7312fc2f2a70ee3cbf73caeec1138021f9c3999c646a3cf498eeb505e91966ae4ca5a57beec5d94c38772ed7e07ce37d612d0cf06fd43631e039dfeb3c4a5c1e9f462f7c4cb438b0a94b49609a857b95d81b0d1eda893518c014590a70c7	\\x3334c554d228e8bb414765dd0d4fe6b121c016f081d2dd28de3df44fe2ae0c3c6de38c93fa505c77daeb0f316957628eff1b25b8b713e5d201aee4794604782d	\\x26687281b8a37c6f0fe3cc92af7c6267ea484b87c81ef3136fc2b602bca6ec0d1476a25f8044edaa15fd75a2fb565e62de4ce23edeb903ee0154ae1d6b430036c754c0189a66724547c43ab8e7a34f903d7776340143b8187809672884756d63d51ace60d547bb197d6f33fe949f7cce578afc2fd3b7b81a5ee62393c03b962d
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	8	\\x2b67ff3bb7175da558dd213770a8f2531570887d2d1022f7f6e16ab6a0180354323df899a4e4f295d00e34ed1a1407b57ea4b4477f6fd8a881ed195b8933970f	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x414cadb7f7b283db845db304c679531151d3a82c6ac48d21574a278fa8d6ebcb15c6ac9a7649d7c301da1890aab291fa1004b3d161d990d4a0b1f74ddeed32b8c2159c464d1076192ea200fab24115101e15dc213ccc536a94ac21c40d3861b5cbf8a966ca0b63d02cb24687f4a676acf2518d71d069decc3dc0294c1d6fe40f	\\x1b69d64be25328e92b0110743d67e2b6b1d0924290c93821cc21a43ad57d3f1e2b18fb1f9cf38983291fea2c054b99fd5b44cc9e44a9b0d989be31d6335e3670	\\x92342baac5c7e2106b4b0ef301c035bb74d122d62e91e0b791a7945c153d67b1a2b446040bb43f6165b8fd470507fbc7ad62a915405d3ec07e75180f2f2bd0333e2202631b17a74d3d305bf53221be29ec6355119ebd1f270fe0eed58751507504f23d4c5c39a4349f0f50e25e5e499d6ecd61205115bdad701a4e96fdd02676
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	9	\\x4683479e47a8fa00ba06a5e1fabf26cb8a0acf0cc5f9d3ab2ebc75b2818e86a81dcd0d9ca3ed0a54e3e78130535b168e83a35fde5f63a1511baf0917274d770f	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x5ee7066db022dafbdb3844130825782302b9174c37932028b1c1623048011e3ae38062fa9a6954a4ef383d04fb8adc17bbd929ac7122ec795b9452481a7687efd497380127a9dd290a280842346cf7e2525259755b4b41eed291a44712a9ce3624318d68cf5776e95f4105388cd99e7ba29cb221a40eb1ed4990dbb13b3af290	\\xf3f17a82f94b2e4a3fed3e3392b8ab511f0742c7af72d787ccce28d5adba182ee95b95e1e2a0c7d5da88f2096d0e06429f87ec78cd5d01be605823f4092f924b	\\x877a123acad31dda0851fa2102282cc5c8bcdc1956cbee23d0e7c139214a8ddb1594a2161d43cfc3b3a6fbf9c687cc262c00b7b43c0e10a516992f9222d06aeb98ed167418b69eb3b6c8a9c36644f8bd2dd49ca24a49e0489a173702b395c8bec2631ce268d56a41e992ff2a8b962580c5d720b65c082bbf9185518c09a6c05f
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	10	\\x004ed07c6cdac7cc09cb7792aac8cc0f6e7bdf5331d6fd5c9aac0193e1addb96f8e3c440d66ddade8611c77727b43078b61fbb2e25ccc52621a64216be379f0a	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x53b0c55e6e3244bf8261c335ad8af41e3869c5867023d419b2e59cf2aabd6a2e3fb5daf02b3afb2c00895396a6512dce5fb4339add510609c362d74ec38bc97ad765544bc57b36ff1429bbd322faa928ee11ef4b035618425d2e46ffa49c6a3267ed05400a6306b7ef8589071beef96e142cd98488f605f81fd87f2fcfce22a1	\\x6169b617e785dbbef23ca7d7f3d1e4c562db907e2378f492b275408c9b9faad28b3683a78366743f357f201a98693ffcd30337dca6e8a3f437d3e8fd4c97a0fb	\\x5aae0dc590040db9e9c23499223b290ab5a2a3a677d0f9cf5d066b50656dbb4ebd4534f649f1020b06e6728bda87203034bd1011bc20344a22f20352615234586130a5ae438902a53afc67189b9a75dd9b7e8b846f812ef2b0dae6e1ef5b2a483fe7ecf30dfdbaefb790652a0ac0152fb12088c41a9b4e252463eb50e739f7f7
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	11	\\xdc5dc7d53b83bf2f7d95bde3b07efaa830c0efe69e856290b7fa41325d525b8e29dd62db753333e8aad9e604326bb94b9f1c15f75fd8437422efcab04df40c0b	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x0555f479f0f0479d817232812c6e3c860666a993bfc8002eabd5ba64413dd3b665308f5c8bfda10fb18d9e1849874229787fe69ed2af04287ffdd27d48a761bdfc5307d2750f1a8b50dee35eaa5a234458de60f008114e3dad5778aafc53aa8ec44465be7d2edaaeb4b6c6e8c10791c1b9ece612ffa9e8833d7a66c4d16b8971	\\xb9bfb112381c6c305979067c43b6aae8feaad678847bd3a1916be9d5b2a97e3bf3c7dcf04de8858b5ba0eb413b965b69af6cf9dd0093fa438e74aec649316517	\\x640af492e259aec3b59785a7b7f6a30c48ee1c55e4b787d615e43446403e9bf47c4c3fc93dc393116c2e5fd54c7666a94d5858b6ed653c8eb010c5722b138fbd6a0a4fcbb9420719fed1bc953100bce35fe1cf0a2f8d1c1f5a8bd0ece622fa088b2b3e3b32d11a09004ad5aad320968695afcceb6e4b3f671961b73858242ee8
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	12	\\xaca7c299f8bbbe93a4157e0d5faf84f934221fda99ba95df7fbfc11986c8987e15d0ce9cc15132fa2dfc611e06bb0649967857a3d0038b49b8ba1ccf4b71e60e	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x1372db676de18a514a8c3cd4bbfd454e362b1bc78ac0c292727b79090535e6923a1b5557f8d2255a8fbe049c123fea7c7069e9bfb2d920e0e9c6f78f0050773e9dcd96289fc3fed49a82045e569072d23ffb3033a2d7e77fc522b3cb044402ba8297941388e2c168656f4cfa38310ed060353222cf4138a26fe94575fcd45acb	\\x7e67cc0dfe6b994880972cdaaf9d3dd3a63401f4662a0a9f360b3520b4c81dbbf606648c36b265fe5f7c73732ca53a38dba005d24100749de94d97832b76aaa3	\\x596076b08b7e26ee60865472286fd563bf04af61408fa9696bd935784887f14805672f29ffec58de5fead054a3f95dba11627d48e42182f349a996fb60bf1693433fdd1fa587d8ffd7af70e8c2b35353e60f23ef9e50b3ee862198ab5a0db08cc42b01698791287087ab0c7e8eaa46dec233679cb16de093a54dd9d885de85e8
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	13	\\xf857f6d8980dea117b484c53ff5487640874c6d0040b7de1ebcf34de695f68f28d3f65581d53ee1939aeab88d59b114a0c9fd832bb8d3865eaac05236b381903	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x5d015b9c76682de9cf9eba7d89dfff8c8aa9c53214b8ab5f81441f291ca3a6e0cdbd849124a2ffee1513f80cbe37186bf55cdd85a130364d883ef3d9931c9d13f42c1ef3012385db79c89715c3d3191634f3667e1edf23898adc3fae6561647fd221e8c919da8a6246fa7696a26c65d5c6a5f074c5a54eaea352cfd2d8a9baf4	\\x2463991aaa531e7337829276e1758c0d0c90042903cda8127ba5f22ad8f5a015aa3ba7c098f590bcd20f8d443208f70d4bdd1aebecf7e3d290814290f111ba61	\\x980c603ad41e4d78b8611605c909838366afeeb7814c654a504ed68948eec04aabb96f21127d3b9b51171d95946aeb161396fc45ef578f89e988cb899003d89510162871d260f59290e41136285db614708872771f31798247157b8034f336253834c9cddde2e2e3b9efd30d1972c65e0197a86eb4239fb05126f0d653071ced
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	14	\\x293588d3c02ebe08d286e89a3504f58a4da28b1a8a8c8eda6fe5f6a9dcf04f4758a2cb19c790680236b795904ddd348e38855071f1c3cf5e0ec792dd0568cd0a	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x4859eefb65ed8936e18c40dc65a2d1f27b70b63c14da9a01a4766fda16a814eafea716f3815d03d1f144925648582f3b2cddb0e7ecc2225f67aa5400fc7bf5e3a94f04787459a181a11246f9407d097b4ac462cf2ea2951be5ae1e2666302714461a750843db68cd813050ed7f1cc7041bda72b75b56efd008e48c150e830c12	\\x78c83bf97af35e83f1b4e5030ba8f801423fd7271690542beed585f8c513de82cf479f41c3317f78e77133faf72b97c4d91d49862c6defaff82bf68ce16c0ecf	\\x7f876650b7f4a43712bc3dfd3bad35596f23dba908e879bb96a0a6e220b55fcb19f2581ccb529ff80d5a2131e9b8b49a328ca2959793bbac843fe2d09f937e299371b001e61d46ef731cf0cbb30b83725a72db850ff1b6f599ae82278c25294dea43d18ba994af22ae74e0f7c540da0636d3cd02db6d67cc5ef1ffdae4b68864
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	15	\\xaa71d2ef421371ac46b9613d75710f1f48a32e3e6206b9b6b27dfb0d9b8d563d1c39d67f62d46495b4f79e63704deb3d1f6f9531b9b636de0b33fa0df2286e08	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x4b9df701021ca5843530456705398240e9abb68c20b1379e8794202600c1423cc908a76531a5ecbcf5765001627b2dd66adb11b5060145d15ad5cd8e26e53475f080a9da48c1e88a5efd055f0bbb343c0539c5c4bcc80e366f859f971638cbb76119d2f4264644cdad9859e10e0d90f424e2979c47af7863c823657b40436139	\\x53cb098944746450485e91640825a6ae4d54f31bb8f752ef1d7fda97f2248aa5cbfba31c38a8d7d80e69195041599fd6b79b8a7d1a4d09ddcfbbf219f2353e62	\\x202f00f34c8d91071679859c65eca28117876d4a5c2e494c20df5fc238bd9e04630ff8fb6c533504ccc101a059db55deb7581820b11523fe607b61d14c0f13ac4b2e25450abaafbea7d96926b351cdc57769131552254e2ba47a6f274ef5395c1d2d77cbc4d178b85ee02ba3f4b5b86b37d5d52973b78ba0322a347d16d554f9
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	16	\\xcc9e5817a24b3f82c4398f794dc960115f6cd0b3613a07f470a8acc56c882374ada12328f6b6396b95f8dd8f03f9fc1aab2a52c81eb6acaf8b25a5fbc9e3680d	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x876f494b98ef0013ce68a0f84e6aa13509d92a66c3fb718ecacff86f9952f847102093132d4515c98e9833cd55c100a36b3c6cf594bcba82fb8a9fac2c1e0ac8df59712b118155075dfa521feaf561f9b384d53b6321d5c7a35d2fe6b2e5d5a2bdba8ae2a4affdf576bfa90d1f36aa4724788d71cdc7b5bb2f71854c3f44288b	\\x49e0a6411527ec53cb25efb7ee3f764557c5b3c754cd5b0057ecfc86ba8c0cffa22f6824b4d8666e6959ad4a9895bd14b3eb437124adab2d0aa1d640fbd19ad2	\\x87b357ceafe7dd618073060f1c81a3ce3d2b13b383f4f9173ef5a835cbd74331a038a3841851fa0591d0a092f06415f6f0c78446175398bfab28e424b97290940e77fc4e09a62b66a12a981970c4d53a414cd386eb72c676c81d3e932a615434f4df7b62f082b7f639fb42452d10a6eba254eb088f591d2622f34336011d0a90
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	17	\\x0eb72d5d454006cc975bdcf907027fd2cb7b1ea7c324d07faacac24c3c269a6300c1a0dff039da61430297dac76758ae1c34567e78c3eeeaecbd14dbb4a9a709	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x9bcf8cf8cd54d4c874d3e8eab1ff6f3b50dc6b37a5d0c89c45b46425a2a762bda69eede3605e2f445494698d89982d8de4e0b20f0dbfe730536e7afbe612410625425181fa1ec066b212f76b49d6423b8b1220b488b040981ff479f8b774bb68699f9a577e6842f2acead1170d4d28fd4b895c5ba4c4313945d658e55a4bdfbf	\\x3ab8589e9bc16382d77bf3b90fa9e7cf2cb48cb426ec973bafca23c9a816098f9ac40a12ecb2f0996eced19483667fa21ed844b598c2b5c142ea70f4cbd99010	\\x377e8747252acff5efdc421f8ac9e25487743178ddc2e4fc2f1791a0f016da9fb7903ef8a26f372fe169d128d945c6db96ef9710ec54e40aa05c76d572a1050691a3c9c5cb5e8fa9ef038962ec861ab3a2a6f8bdbea67b0a34aac651c719f653468cde1e056fe7dc90ebbdcc00dfc7958da908221bf134db591ebae953f16e34
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	18	\\xade4be45e1c25aa9f3a756d78dc8c3a423399b61e5cf687ebf692f8ff98189b85f0744d8abfcd3cc0b0acbb7e8808cb68f664b71e5e2362b301cda588e47fe08	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x8c078f01d502f758526c8c8fca2d005076387f9f830878a603b72071410a5064eb211cdc29452292b861262c64f08186c072f3819da3c55a9181085d80a7013a55f28b97328968fd53c70e04bbc427de48d720693e4ab28051a361c34c9ded38c4ff6e45711fadfd575bea630a45a6da182a2e99d327bd4052997d7fc4e352ad	\\xe38bb44c5dcdda471c07c8f2125d78ddd834d1294ed847b43d3a4dcea4181f023b7001bf08c52788f5a05c50da8db4db727dbe3c4d3894eec2d442002120dc1e	\\x6b232fda994594a8c463b6b273654a7abe181af776a7b65141cf18a1b1aa2fa699c381b283c34e843aa29342556c8db5a07f29e46354d90d4998e22951cd3b6b548abfc8c55a55f3f84308ae4da9456556720b4ef5c246df9afdc597a010a5da1ad0d6d095db9b162ab34551bfdbdd611f932329948701ddb4c788b0cc4915d0
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	19	\\x697e1f991f1bdedb2692fee4c6751ca13606a5e5cd22000b61422141db6f79d9e41b8ad907e65491247fed65c535b5fadac40dd97143896087dea0e7ac3f1e00	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x4a50902c3f761155c423e7b907162047276cf0c1532f6fecc76363a77abb06911d59fea7ef22cac7a5f7926e10474cadf7cd24686be758b6cf5e405942d1a7a80ee0400a0af16d6c28c256834e36cb4dbb5b51cf8098d95cc16beab9ac7a4736c2e612bd6ed24f3aaa6d4f837c4280bd5962c342672106d7272c97e1470179b5	\\xb9a1552546fc8bdb3ab09c954559f524ef7ef942f6ee06ba4c6df6eb112a81d9694e52c278b9b4db172dfdc58c91c16e2e60dabf3401d2044e31701b584c1bec	\\x9baea2b7b8cb865376e86bbbff9e3d6b4025e4d93bf792ea2f4e2b990a99628a2cdfeb230ea657e3102225d29620669892be6f1af24a7ae8f6ae9e27853a73f9898dcb25946f9fbb88ea5298539084cabe6bcf6837b1d384cf5dfc20070e30696ecbb144824e93887bbbb6a8315f6d6fabbb2c8217b345d14b95194b6af88c11
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	20	\\x2102b3b2d3445557706035b9e48187dffcb24d6a6d1168b3508b4632fc9e06a4fbfa759b8c6baa9d8fb3fc6cf726e707583d767075bc340399937630a301e606	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x534fd2e1e3213988cf721076948ca8a01b9e51af9c397cfcce6253b8e33a10a03c8f2802d56c61c2cefd3caf5c2b6efb3528dacd44ce68ba51ed64d284b328e59e27dea95c27cd3d9b0069817acf3ac94d6a39c5b24eb9d7d56cd14f54e8e81a4c99370e1693a8e7881114b5fd0f9ccc9cbc872a2d3e6d8e034ba5fd8196e819	\\x8cfeb4e0ce7a63fc416f1c085b00c714b2114adb781beeb3858d20f6b3d237431db2380158898793db2dc230ba6cb193afc8c0aff7100a8b11c54482056c6bed	\\x7359dc53a12642e5b54cad32c1c1ff20eeb703c2355364f49928abd0ddc625b5a993925125abb5043fe0389a665bad5bdaeffd39f1970f148608de2044ba50fcd3707817ee9407fab20fdb6c41d59cbe2fa95bcd4fa9f0e7e4b9f7558421bcc959c3ae52732fa6b21f300779f5975412a153bc13bdb63600041ad25bf879063f
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	21	\\x69409da9c2d4e530312956dc6b05ec8a253db7a48151fa44907ddbfc420fd3ba3e9edfa34e8a27352ede5521734c0579af7abdb7729c42ba5f9a7dff6257430a	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x233662449fab89733948595809683d09ab2ece527ebf65c08079080fb1ff4eb4ae0a9fd142bda3d81b8013956a8508ccff406720fbad404ea700b7ad431b7ccebd82939f0c88f1a560b6d98bad603b4d1fe93666e1c1ff63b04ab4a0462f32e8b8efe17b0113955294a748989b14493831e1355f940ab19a8a00cf0b3de865c3	\\x4d055c88b7ac264da1208e0807fcd3943d7f29ccaf05f7f7bed6c3de4ab3f3335fde15ae7f92bbffcd1f19367dd5b34bb4416f0555f90a69609aa6cec407bc1b	\\x62530c82cc84b2956bfb19ab910ae11a3f9ccde9c6e3744df2e800d4215a49035db67595bd04fde8bc3fd5ae1e0438b164d982dc887968193d798e060a644cdb1324732654f43ad26590d338b62ce3ea15058a38d000efab6bd87be5cd02b5afafc4357224ce447561af4958bd6f592f693ca2b561a06d65e41e76a15cb1183b
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	22	\\xad0529e4832499f2c04af266402274b531e836b365ec4dc3488f0915bd7a982eaf98dc1794fd1b63503afb019d34a991abe86c766628801b87c8551b9b648d0e	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x313919728e4f013c76980dcc378e5302df045e753d14ffd477e9e898ffd88c314cba501cb10bce9711de7d24cb6231773e5a0c4b52e8144b4d2e1fff62a71322540e1e7c81416cbe389bb258d045539c75a117c5178921e31c02e5455938cf5aa63b19a2222f6c18c9041fb5b47152abd4ead3d0e8d03f69b0f950343b7e2b06	\\x4329233fac51eef70759145fb794035b25e71ff1ec842a61f37b29c3ff29904f5897eb6c00a93b9275c94053f30079f37a3e2efc2109e188af61caf2dff45687	\\x8f31785790810b08ed7290269e64eb767ae8fc7ea2cda7d7cc1ea77315c26c5672b695765a9a1bd8886b1ed4357a57e1f8dbdaca226749fd9e91e0f74e6b55c602b28bb253a6b3bf8ace878a27c9db3760df47f4dd181667fe754ed23f490bb73c45ddb751ce92ad3b12226dd1e5e859e6fa85082fd5ee6100bf8375d5b9eeb8
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	23	\\x3359891982d25557a980aba8d003ea12673ceb7da825ca16b48b50fc438ed64e7fe0b0ae0672abdfef445b55e11dddda07f350aab3ec973374fc07b587701a0e	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x3573a2d9f7883327b03e776c95a6a5d7cf35f89dcbdc16515e869169265c7f4246f537b2aadeb9698839ed369ff6717a1ffbb96edb8ac6fcb5ec52ee81795b2cc3687329cc965b4a5bcd8f687518b47ae73364faa171edf06e6b3684fbdc6c9d7a93b4160346810749efd43d46150f57e5457e4c921fa990ce82b734d7d61e67	\\xec6a4a92752328869f187f44c95de79513920e53747d66e1ec93a575acbf36eb915e9464a5ed101b5bb852df958c73528d2822d72ca59a50182b4fdbe514f7c0	\\x6ad580cd29c457254e0b45f0c66bc557fbc6a12292f77e3c4a7200cdd75674bc2a9224f798b9377ff0e17ba376aee45e8bd74a81a0913df116bd25a190c4f4581d41eba89611545ea4f4b0699495d93ccf86e5a96b3174f9bbc2f5bf89100cc69fa4f5868e08371fe1074d2511f2b2249156d644133a9a063b76b4e0cb57962f
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	24	\\x53a78c9657a1c2b2048c03c7c3b5f504f858a1b538e9bca68d3fe96d604c76761fa6230a11d05ef3019c1097990b4d1c2dd2f2a4f816ae5c258176059979a80c	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x1e6845bbcc8701ba09175138dee937c35dc49cff2f8a81d77ab62272db1e42c0e9fb53af9c32a21c7c7df687a07f30ee0345802726c0cc1c08ee01057f893b7d81dfcfa2c8b1b602c7daa45f4c04fd1f68ca301fcaa607e698a70df5539464fac7812eb6ccf7464d7657f89d26b12a713ad7d0ab42d47d0c65b11260f5a753d3	\\xa7aee235ff2c64f1c7e1b28ffb222a79291d77b3b8acfdc8d5377ae967cef78939e3ba43ffa4d9fcb2df093a6f4efbbd8d95b89ae6b0e04fc24589239534e7ed	\\x69bed66f708b131f231b58225557fca1539ecc90e4032a2e7813f9db79809b38bf006818d834a65eda3ec616a888ac2962edd929f6d69b98c846e558ae7beeb5a11b339d98188f602568a09bfce69efac46dfe6813553b9d1360a99d46b324c319096761392b7b1b69e9a4401678dcbe5fe4e26e808d571a331dd4f2c2e48e2a
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	25	\\x13062299ad93b6c992d405f40020e72b55fbefb96d7322e7f39c14bf15561907930c93341808bbd108a2a87ad5ca9a5842d290f217978cf61632322de4f9600d	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x9e491dc733cc57885d7a56e000fb8b364d4f0c500a01271720aa4eae6002833ef18bf347e66649c8173d1fe3611db9051d498f1bd8d1f78499ae9c67efe40bb1cf6e3029a6df115534358a0b3ac2be1661b1588e1ff490b78872ef0f7a517a0ccdb1f6c83b052e1341cbb7282a3d88d465861d6a796f58c232c072dd969f1b8e	\\x0b4372c38c3052ceb2fab33813831d4b2d07022a80186e03a13d091b96355415246ff70db1b1dfc290cf15885f85bb8e149cedea828335439096e477899867fe	\\x0e1f3f2dce30b33c1cb611b4183d45126d14d1597b4cd2a59eeaab1783d0ef2d8ca853d6e295962a7e28957d56c9d23eac97d1dd524a2d0648ede78683d0a4740c25847e4a19e20300e1dbb37fc9497459eeb2b6df8d242c2de1eb06e477ca130166382ebcf021de8607b2b4d0fed1950b187bb0786563073c3d7d9cd6664b8c
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	26	\\xa2cf0251fe5b6a66ded3237dabee2ae38e98db02a06514ebfbc6a1cbc9cea0aff2516c17b5a6e242b88eeb60a0ebc78e472f57354754b6be66d255f91ab6660f	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x3f66cc9b77f56315eb1cedbb09ade5b4812788d6b92fd02e1c8523e6ec2dab01a6b127aada91ee418cc16c11eb04515198430cc30949e20bc37e8dfad29fa43a9c77505e56432d671fec46485b587e571199cd7460f9fb15d586c5366181bf4f04ac0e9d392c7bd036b7d3cfbdbfc77acfe399cb5bb6afceaa4f8a8e3637c0d9	\\xb98014821679fa9a01da447ad9fa987f4eb1b085f38fd4b79f11c0debd2da0ed831931cf2f5bf701b6fdcf93f37e8ccb891410056787708ad3bc12ab7cbab21e	\\x5cc620108cd60aae6d7a8f20df3e65f2066c2fae9e319babb70d9653480d61934f5f77050d01fcb1cd1bba4d24c990a144e0548b9549d83bde3e8d2e69eada78b6e20874230b3d84e84b8944b84a2497ca1eddd26e9e19f9b37e9f3bb75aabbb5e276695db7ab0d6fcadf16b98e81012ecf3c0742778b179686876f915627ace
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	27	\\x80a8c22f8437fc387aa33e35fdf61253ebb1c610c7089d1e344bc2a9e80efa764481816059a9255b032c8bd2a23ded4946311e196338edce98db38a1d3a3070d	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x1ca02c2c0eddff16d8297a76c9ab25d487256507e1c6a3a65997a82ee19148ac83a605d60a93b1f53f2aa8ae07e4ecab3f5b07264e120f2f5981fd154ab5d620c3153a8b45f89fc788738a3e7aaa99d766eca6df0ea82a258eeab5524cae82c7ffecfbf90d0c5dedfb5450e50661bf48bbbec4c449c109410adb922ae7f2ec0e	\\xa1f242e30f020fa3d24749af9d4503ebdfefe7542c5877e3ebbb456f52a846760e12292fd703b42c9fb5a92a319f363bf432d452a6d3e061f3055b90c3ac4ed9	\\x17699b74a8f2ce995874366aacca612bd2595dd5f28a34e848056ca60e71c8bc0e4782888547b0282758b1895414773d14712363915fb4024c95829db04ebf78997dcda8994a9cbe88946232d1d23f05bd6e8d211674c32ab939f62234d3bb33de97873616bb2183ea393e36160fa43833fd08aa771df66989e49954200ff945
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	28	\\x5bbd63071124fee375ae6aa9a7bc5a93f2de9cfd2ed19eb0465d693d0ba7e2aded0ca0d62d93d177054b84c684d24ca74897a636d14e105271254d159fe6cd06	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x58c6f5cda39c0057f1177e672b18dae9cdf9c710ab1c4c636e5c410c2199c17129607b79b0dcfde10809d137636daa0eb94f41d8c3702693350a7a44528bee42b783c7eda3969f96988e2cdab1a6dacb2c0e5230ed62457220e3ac0f3d739cffb11209bc9f45de572a2463528afc715af5c5ccb016055553e8846ccaa35e511f	\\xc615f01706efd9ae601f1450906b884b71e9ccb78711be8f78ccee3965fcc51d57988a3d65c117a2393796b7931d0106225a5f748d4c83680ee32f42fe18f889	\\x3e0ab18540d68d089d228a87ef4eb46ef2317ecb79e4fa9ada081fa43c1cb6bc86353b30d2ae90070316a894b4c63985235e7fcaab95501fc9a8cb1b8c85ae0c2ddd07faa87affbd7cf32b250c954478432288d25a25e73e0eee56c9034e8df1b548b02e14b859946f041997e0c7a2d60bd827dbdbf991e0c39c1ae3827d304a
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	29	\\xd0f8acdfa5a834fcb5bdb23a244ad4491636690f5d707588667d9c737952931e69cebf7911749ad885027c791d0412fc0a93610247298d8f1519ce967326800a	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x85d81c98c4692ca7f706e1bf7c4b13b792d49c2137851d12d70a15dd22d7031597f8f40e1751e3532ae20cec67ec3bce46bb8aa03163e42948e103c96f4148559ad00d22f2d488c0e73b41cbdcede23ce9ad830667bb8b6bc20e387a2bfe92ec27bf5db060c95a462a85966d327ee40a91a4e7b09fdb024ab8f3d7abaf7f5f41	\\x6ad9c3d212ebc388148cf6e79c17a3b1c6fdbab1f53f5157d58840dc6986e27ccc86587f5ed2984ad5292a828f50ac79eae968ae9d23ad1ec8668ab4a6b7598c	\\x3d8128435f4f6f4e530394c6dad077f7a838d20c1d86c8814023f5edc78dcddef59a2012683d6cdb73e0e90f92f4800294800436476c458ac49bf8e44f60704d11cfc9e1653464802c5e3275dd635ab69bbbdb7c6e71a2feb15b9dd410e9904d0045643712ac8b508c0a712759ab3e0516277df143724a251ed63fbf8ea45a9e
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	30	\\x22b9676f5cd25a0dcecd3731cf64dc7e7ff66cfa5856d7846f95574049bb629499a7c81bccaeb8617f9610a854ab02b1dd6f7e4d21ee34672eb29c238f4f9a03	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x4eea9839a53222e8b88c32d7716288d4a7ad7faa84d13e450907c115e8906851c835d1af8946fa3e271734b3bf9f7f5ca8af3938c9e537355b021588de165f971f68d75bb6672dfa2bff630ec2d7f521f60825cb98f8915ce2c60ed8ff63eb102f8fea5df2b80a7c1d12f1e607c421ded0432dfe2710d924b3369d758d36dc51	\\x2c074d7c91a0f023cbcb808d2bf5d10b3545d0e0f59dcce0c90827479842c868cca2632dcb86594af92693d5a014ea3d110e754e3d2f3c69a85c21235ec1f39a	\\x73c724d75b8568ddc5a25d49a2a0ac1adbb97b65de8ee83bb9a5e615cef7b07a2aa4499934c9045ef436b4e0a7e78585b52fb2151a60da6e43e1de282d26d208b00f461a6413c3818522b22cb4c8f00ea97da1e2393faf724fac8cc465c5d8cf3f0185e19ce8f108d8743b792a9b3cb5caaae3113d389742ec59f95c7a17ff72
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	31	\\x6b1962b9b1579d6382c05c4efbe3b88aaf523fab16f54e3dd8a00b3bd96b765060a5cded82efcb4b02dd5305308f0ed11a1c799b8e32f8dbb1a3fca82ad04e00	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x13dffd1a6e5561bcd09683f30fc55d621694d5a7d73c6057752b611a511ecd884666cce51259e47f140f7a6faf5c5c37494abda9bcfaa574d1ad0672c3edb54bab1c34b50d40fc79153f8c31ef65f617fdc20e0d824b61f3508cc61fb072ce822f5e07a4c2b0a71423215da1f4981abc2f879ec2c80d060a1acc49c91dcfc29b	\\x1ad7db24e28b7355305b51d2c66a77b6a68eb1c4842cea41454a41a018f76ed5f3b8cf139545d5844303b3d5f0de31937fa9e2673c8145c984f71b24b7cb0d8b	\\x32b31a1b9444f7557bb809348119632f4c0ea8fb0b679c287c94dbe97208e1ac1fd4fc9ea3f83f3dbf4b63f311ba9da56593b35db64e22ba07fc7ab886297098a7bd9139f4f0628de0085b875e307832e9e3254a7f71b3c0f85992e049133a388725ade74dd9c3876881dee7d996b35e426cbef3d3a99febfb9a94724847824b
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	32	\\xaf7eee5c1e51ac31896207207ff204965a4bbe998a729177454a862f6dc61d610d6e0466c37ee12f2a9eb5414905bc2b63fd5d2633fbf54c774859d740e92900	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x811d68ffdde61f97b4ebc8da0884091b8f32717c4e0baeab7f759f11e836fa3e90ef299774ad5c4c34be1865bdaa9ab3ab313e94228635d6d7658f0028dd790890509b6141d790fd6aaec0714a072e1002ddd76f03afcbd0d886fe1e6e3bd9c98e7189de4ef582edc0e12b0d401fd8020ac2c95a6792a8f6505d18bddca47906	\\xd44cac33107717117b3f0a2a8ca2903e0b7096a1a3dd1ea43081158d435eaa4b11380219bb701d1fd53c2ce5b1a4e41f35ed502116869423f34ebcdb82075f9d	\\x94b1e6103f5e05a8c2fddb1b6916393d95a1e21baf5bcdb1bfd15dde1008d764e91c6b4db042e943a6dfb5b119bd7015f2a6350da338f1321616d205f486bb546de965d7c1e122e4174ea3844b0844e4317ba344dda651e2c83affbb779bd15e70efb1bff6173c8a0009ce5ca19ee8756baeb27e01dc86d8d35ca2d349e15680
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	33	\\xaa8487ba7c9dd5cd202df53d0e328c46cc4412581109d16b91914c9443fb1272d0e96bf88452b194339980ab1022634e28f7fce76ad2d719adba92cf37532e09	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x04950c9816d00c55f3528855b9f5d0f1380d40a20092ec2dc7c032c886285851292687fed89b357327dd397acf978f137dab21140edd51f341b31b4f5cdf750a2fa9d049e8ec71ba2e5bab8b165703eb8f93631d9f32443aefa59fb6baac9ab2906429720bd47cd9242abd24b9d469d958f94aa0414521c0a6d8149219c8f589	\\x09cccf67e0132a076c0b23f75dc2fed9ee30eb99359457f467c9c3bd1a4ee3ff22f26b57dad03c49f5b7ec7624d29ade51279c908dda1b5476428bc773991330	\\x4811503235a62093447b4d548740a88c72304f41f588139feb9751c7044ef6cfa0ddd47074c858ad9206d01eda8de1ac7d385bb7c9dcc4c1024ac103b6876965eaa48e1a1d13da93722f264042a9482a5fc52429844941779251c8f5bee83025da7f2a1556591bc570de218547c72c83ffc087a3e9137b794cb41cc5ee5b2099
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	34	\\xea66b9d73e19488579eb40b23446277ce5818bcfc8a0a8063072a73d26e0d22cf842186c67193faed510f6e30c58b0e1783c84376eace25b48cf12df391b6401	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x2fe9cfb3e5fe28d8a189a82d5688e9a5dd3bc3fbdad76add818536e03d2283fb267eeb116b02733fe9129d7f9c07236fbe0bba57824c4d1d817b36bbc61170e8a86a1ef6aa04f1f629b4d267501fd09351585dd1fb54a60cada5d405cc248ed3858eae04d71a15500abd6601025b1e3a0e38a847971c5ba64cc741ed591e1e32	\\x14a252045bdf8c24a950251a79f52334c2fb64791d39c46ac6524b58140419f1cc1378274053a78fdf9ef2ffd47461e09400968a345c454a0f4ec06c4e8a1109	\\x29665d8a4f4292179c175dd5a98ac86fed382588f2f772ad1b7e13de77213d5331a1654ab693836c0cae6f08d48df3b11dbff44569f8d98035d1ea1819b9c669735a7a900946c4b44e2d5713c0c737dfb4e3a098fd3587ec2669c14e3e2519a88d7783aa710b05597e14c465dc60560d458f948624bc2d5b8a0579fa1af55076
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	35	\\x2ccf300289920d395722f3560f73c53df748753d0548ca8d242251e60e8dd35c49236883b7cba9c1551840b5a2179ea7e0c672bbf59ce929cfc4447c5edac908	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x68168179dd943c9683428eba243bdee0655d5344d784a5baff436a910566f58ec487543c64dca5ccc11a7cebc2303169937e410186deeeea196f2f8f1a64ff50d506d08ba2eb781e9e3f9e552f6efdfb05ae7bc06088639e2893d211911f43aec47d80253f4aa8ce74649c137710983283ee1de46ddf2bb269355254f7f7bef9	\\x3b1a6192b929b67c9ea7cbf3cddcf6c02f04e71b2818b5577198ce2470aff3f5b69fcaf12ddb396f5ff9311983b8aefd5c5530acb76758cb4de7ddf8922270c2	\\x437da43cb37880e80c3912873384219b9b9067e7f4c1cb8a86070d7ddc9fa54dfa61d1681f1365acb492f58dc5f90e524a32a97c82b1ebbb063e66f3028ba2c564d220fecfdaab403872e9d2cf7b5c9714ee599df0c374e80b9f02b52a22af004f5c9b7f43f8ed49ab7f00cee2b3210f094483e5e96f4c481eb2adc221b049b5
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	36	\\x54655269ce20efc03275829ab09b5fb28b86cdc57e22427db342b3a6da18074fa91599cd4709dbf7004d95751b1c2a692bee1d5ca1b33b293d18bf01bf051603	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x118c9034c251c01faf738a6613dbebc4778c2b3c0e84d9a124602382f34963637abcefbea8f2c1b4080bf84e15599d7c0d20a41125382f245045246cd93d9b8addaffd71dbc93d15eb7246df6f38d05b4fef7cc66969b3eb51023a7bccbf9cc78c9423eb9c977021c4c6d0056a3c54e0ec22c12b0fd72f268bb8d3d48c8b5037	\\xab7de4b51527fe620f1745fe0eab68f04b3192837038045b9304c6a6dce386e5633184b2ef332a42c3ab04d779393c32dd3e27df387d3606df4671e67ad1b622	\\x11e88e8b55f6b07fed31bf87402500dc8f232c9cfee9e3b706df03ce9dcb0f1b1cf8434adb52a12802554d0f905b13c8985781c3bd4305dadaf873fa32b40a3baabc556bc807d22cbb45e1cf8b057fc80b48937ce089e54cb285ac0d1db3d2028488ede03fed76e1cbb014e8a329e3ab55382eab8bd6f0007e013dcd2c6626e0
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	37	\\x5c22c6a8d4a8d848afb225b6738ffac35723763b40f48814c49f41f5d00219396ae158b5f6625079e7003ca174587b11b54fd6f659a57450f13cdf4f1c4f230e	\\xc6f5375b55019fc366e0a236a63152a4bf14c2bf013a91cdfa364033a7ffcc723d05aff50c6f3193d875f756f175b5da8036928abd10f1c13395ebc263d70871	\\x8a8833acd504f2788d76f7cd1326681af5fc1029554b2bde8a103998e410d946394bc20bffdd666599536f9f572bd99e6fc25dacbc1f2e89034463eee8a52edfafe6d77c6a9b9bb0cb76131ebd5f3adf8b7de465b7206a64b5aed1d64b8961a4deb2fbda0641380596f5c5632eb87463ab0165d07cdfc61cd1be21484f634991	\\x42cce37288a049c119479dbd918cc86710e2a2ba34c5db01281a8731bde39f9f1407e4b60ffab32b74b72de4e9dc8d1ed1621934e3f3d1d7d9d8eb44521ff141	\\x433cefc50ac3cef1dc2b3192ae948508f43f4f83d41430ce5875d3fef3f1ae4aba265d2f4d3be49f0dd6474e331fef3df837eed8e1bcbef49a7646d35f579b64fd086151fb8323056bcb1af8a5fb666121dc5eb90383a9bfb8dc8713220e5cb1d6a0ce92c48316f253b137002bc4c4613d07c73914676fc8ab9b4fb6e511bfca
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xc6e3d1bc0c3582df60fb1e26d77f727ef3f7683d3819e7745712678f4d27288e35c048b6c5845109d180f714cc7bf134eb00db45f5dc4a452c858845f00adfe9	\\xc72d44fc4c179ffea430f1482db36631b0875e0554651e6bd8ea7701f6007358	\\x01990c6719e7e30e7b4d9729b131e0cfd6f6c63da5c03372b11ca6caa0948f5577a5c60d4ac377cbc0c6a6d37b92f4871fd5f3b355344fdb47af00253785e1cc
\\x5f48a8be91db02eb7b580a169f60eded419dbbdd078e2d3359f4bd0bfc100501d8884aeabfb50e566dfe660c862c7bc068e0e348d61255064d51f46b23e81e9c	\\x002c3797903b33f349327a4280115adacf36375f8a218f0da70396e39bf3d132	\\xb62c2e4a502a8bc9e9e6596b533588639c90192f232e3ba6fbd55f62160aec897f7ba02730e6db4b8244161cbe33cb1dae74369d1f9e13489105762e0d026392
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
\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	payto://x-taler-bank/localhost/testuser-lhtoyOhh	0	0	1610544402000000	1828877204000000
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
1	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	2	8	0	payto://x-taler-bank/localhost/testuser-lhtoyOhh	exchange-account-1	1608125186000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xd5fd4f5bf8dc651b20a04beb45b1f4ab990863049b3e79ef309fb15e6e30eb358a7a432ebd22bf80a6600e14c6230b691bfcba8602d0f68835c1064c6cc5da7d	\\x91700927537eee3d025c8517539c019cf48f363d00955a91b1112f5dc692eaa2b944454d5e493620bead61fedb02819b304ae542d5ebd304e206a32a243c145d	\\xb72b0d157ce3b4ce39dcca0bf411e23b916271ae45e2ebb972f701425f16534bba234cf125252a3c22542e02ad19ff3b30290925780c2456bba9e473d80bc13c26b0de095ea47419cb26fcced8e79d67d3f79d47e1da9bec81b1b8ced5ba83e6f8e95646bbca45e04861f28b49b47859a9d590cd1652ab8caf1bbb015b6941f6	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x08bfb8c9722a1a068d730d1d52538fcb992bf21af96a5f01a8afb1086c7c0e77d9f706d7e810740453652a05f6f3a311e98d6cb18e8510272c1c308dc395910e	1608125188000000	5	1000000
2	\\x6d02eb239946cf8badf99ac3c1fb7589dda8081a57165642bf195a5e2ea1bd2f789fa3d4c5e20f5d9e4e5624c36e353834fac495572d73685060439d9848b85f	\\xb947e342d12730a7af9113d8e65a7a7b90bf9d6f6925667e296de73bc22ee767e12f6ecfe8364b4c9b269a098aac04fb534290908f2443315bcec775b4980a42	\\xb27720d6148355e7e35aee39f13ee26a56092f1c477f2e7b13c3e4c4f9a94ecfa32f6930ca473e9b7ea944576ffd586c23dfdfe75e59724048e692bc5e09a1c5f1077950377e3a6fbf7515f0f6ece547b78a0081affe38909ad91a25811c149bab9340a6588ef9a656142717b6810816adca70d2f2c6ab0d26f522c528b11928	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xf5be6c0972c6a99ebbc781ecec3f62bdcb453714edaf70d35561c39ccf0a971e015332dc1a83da83a3c5b820f8184e2f59bd9dc4512ccc1b8032b52edf27240f	1608125189000000	2	3000000
3	\\x6c100e25e5f353e7fd75117dd02493e3b3fd16b973044ab319154b3069e7f9052b85936f508501b1fc11f9450a4e8f421852d6d8c206330554c3a4d438750510	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x9382069ce5aa851a8fa307dc63528e53b8862c370c47a568789af6f28d43e3c7494ba860b734b35416951b8e707d6c4220c87dde3d3769f42020656aa920f69eb5c20d384bc3625204136662808e2081d6546b9498acc1db89b118d3436b08a23af3d60c97e134d969d69700c3f4f60772b3467e0ff37535228fde69859c691e	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xf9488554cf9f0a4ac33606976901c30a08e36ca460fb36a6ab053a30851730c8cd4be99e4ffb0b04aa61b287c166e982a7de2eaf15241f0e5c820f8ce098ab06	1608125190000000	0	11000000
4	\\x0b151d4c34dcb17ab762b1bc5387e83e3e87ef56dc3ea5d2102cdc9cf959e9a9977f86d355c3a8916b28645f7f9f42ee16d78ac784bbd707d2cb55f55963a5db	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x29fec7545cb1189a5ebe0b76afa6dfa3fd2f099c655f450aa4c57cbd623a0927469391cf2f2bce446ff16fe51dfd21395b3b342304fcd1770b13cd7b7fb1b8fbc92adc3d6cf59434feb469762bad2903171605879aaed9b32396fb4a8f8bd562a8658ad926ab7fcd31dd52821b98552afaf09d516ff89f5b994ed715b8d7fb29	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x33d22067921e593874616faece459ff70789b7463bc9493ee4001df4915320baf2dfcb21dd778b8096865f25f50bd6b86fe0018412baffff5a9b5babf8132c09	1608125190000000	0	11000000
5	\\xf43f47012dd7a43110f8d2980ca709aa813395d333977f0182da9fa256b900cdbd824191b225b7916c0d1731d122bbe0a96f188802c6afc4606317c3a277de2c	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x5cdcba46bc545753f3adcbebfd03cad616d5ba533919d9c238b0688cc913d44d31f5fd263418c422df22c9e5ff9776875c0dad1ad3feff24ddc9dd812be41d06fe14c30ea2197111e524a54103b6edd4b16da83681fa3b08ad83ebb1f422cd441bec379451349e7d561398f035602f708ce1a8df3d4ecd3e32d9654063e83560	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x0a626f5d615a10618fcdafed26dcdb632a2461fdb75e448bd89b8abb74fd2c635470e62f36e94dd1bb6e58b3e99837a2707fd7aa62ce6bef391f29f62533b00c	1608125195000000	0	11000000
6	\\x8317c1b64a0e490e9f86fcd77962a97854c33cd233037d6e8450627e511d7d356420971956a9d372bb8e7c2252721a15f3af167971a8a1d69e3815d5b3882cc2	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x8ac75bfd4a19e705eb993ce79ed33e34e6bae45095ee27ff2ad8b4f03ee41774bb2473e405a7e160b46300519f1518390884812bf550a6c638011adafdee369893ee756ca5c622bdb829decf1ec8ef086b774da3277ab643f7fc8cb06ad0cc7f182d06dc48318d5ab4008a177b5a736e1cb9f083081f4437a7bf0683199a23d3	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x96215e06b7469fec56117b7c8f7299561aa5a764df60acace279e1adf0c8af852e2270e5e965d70719a8960ecd30812e14dfca0ba65ce98820c6aa2c0fec3d06	1608125195000000	0	11000000
7	\\x4ca630fe1f6a20eb86a7060cc48f41aeacf6e38b23af31919bc0b9691b06620f579694527cd9c1e8978fba1c351d449be9d9ebfad12a53c1da88d7dd990b3bd2	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x91d1e98c7ad1e264f7ffd11d8258096484ab860d88f4012fc296f57d9d69c8ba4e6613b4856b4ac101a2406800ed182646eb0ac04445e470a6c7b3ce86fb6fd20d2e8cb503e746bac23fa570375af547be076e8990359ee53ccf42e205c7b7881abadb0f2d6514c0162d1f5680dbba236945e8749cac74c644754b17f108556e	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x69f07ad05791adeb352d9bddefb93eaa32d0995b643dcb0d97dbb3cc10efb15de06951211e3a38ddf43d41de7a40cfcefc3be94013d9ef12d39f537c1e26ff01	1608125195000000	0	11000000
8	\\x86a01aa48231929be3fb6c207a842de27e5cbf565fdebd43fb24654cac7280d353c05663dd7801d4f483c4d6965252527950aedcb0dedc993b2436fddc65cff1	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x105fddc762982488385fc6350b6b2fa7101152597b5466bdf3cc3bb95980405fbbe01b7f3ffbc8c5f9507d90ed27938bdbabef7e31ecef1fabcf80ffa44376dd7ad04c929da630e46fc18fbbf918fbd30a2a9851fcba27fe7a584fe912b717e824b193e3861458b21ad0c0dbe7fbe99afc6df01852d70a9113639cac2a82ba0a	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x19692f37dd009b6165a00ddf868c5de7260a843125ba4531fcdd3d620ea29cb20ca5f573548fdffa9f653f61e338a02cf663a2173b69e215ca427947ad709206	1608125195000000	0	11000000
9	\\xfbb7c00375326fc340d1340de0c446b024fc6c1dea36be35d3bf610c647241a4c5ef8261eb2ac7093b69c4ffc8862b82cd4d6b9afb304aa7e5afdc7f92c5cb3e	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x9b8976a21355e84a0c01573e5d50cdee48c576a13c0493cd81e6a31966892464a4acc309516ea9c2d752e72c95cc102f8e16e25ff70729b40f7135f7f55a7bd2237bd63b7dbd98a544e3a54fd01cece7423305360928accf0af550f6d2e08f791dfa5398a96d21219190012d681df6c1d11b1a0deff492e851de363dabfb8c6d	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xda1b8eecc7e795f6c822f008659177ca69fe4dd141bed04cfc12ecea5a7ef5c9c9eae21d91885a350b586e65ff17890622614b5f97be61753c58755f95dc4f0d	1608125196000000	0	11000000
10	\\x79bc8902cc6c71110398fe364231e44fe17ec2f1317ec225c312ffce68a0184bd0f960c5e0e8332f51e460c0b7b5006d830780aa9aa05a6d456e61a5fb585606	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x0bc8b7bb685becbb06f857b45f7e03f1169f3ec61d71a7856c84b58c6193c7ee3f177bf8997c52d5f2cad786f4782808d7b1a242a26eec56c16020bc5b7e9bc30e4c7cae1af4b02c1b336fc2d8d9d2c921589ba6a86ea37bf23b5346f1177fb74eb72f48c3272132c2896d9caac63ea85ee4e3591b0bcce493b904360efd3f10	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xc4acabf778a1917dddfa31a9c6867951f16d1ee3eef2009781b475cd64400d434dd6dae31c88df46724fb932a79d6e4d801a840106c64e7b1656e5cd6721800a	1608125197000000	0	11000000
11	\\xf506c3e2d9abe4e29f0e52cb84bfeefb87b0647f4c41cbd9443da53289286f1d44478fb031ce10fc756934ec4a119ec20cfebf8d0ccfbafcd1929e493daacc15	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x28a3dacf12983da7cd3276abc32ed090aae5c098818f1bb1ab1bf985f5a7212f8f5c44eae01080d3bf97cbca3a0e65a85da9781be98971ab73561cb53dfd7e36a138c1103f5815184217d0dd55dfe7e3be452eec72bd3ae93e7908af24f800377d3d3bad6b3e2ca951ad0a4be62fc97df182869f3127b493e5028027527b0ff4	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x585e1aafab2d354ac87e4e3b1238458f21ca455a3850fd4cfda04a13052d646968ff6d925fa6c3988f34b70a5a9f32d270bcfa00633e0382d3bcf2771501c208	1608125197000000	0	2000000
12	\\xeb3f104c508235b2b740dc5c34c8ee9d0f8eb25458cf54faaae39be5e8e8660b85635191e2b0f6635c391a97ded3398f5102e079dcf86ea3eb7101a04f498b22	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x5634b8e166d20c1302cec20d8a7ca52057b061afcdd3a2a635778c8122208dacf0f6631d906ea5ef0f812a7d4f506902a3635426730b01981ba3d6adeff37d0db8aa013116b361a84f55178242ccc0efbbe50f8819cabc2e84c09dbe441b87200f5943a00ce796265fca737a244eeb57758f01e9c0f0c87d05488e5f8daa597d	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x4873788ea375f9840a5a16a2df5bae8ffd30dc73abab2dc8eaa31ffc907ec69678d42afc597f4c448980274ff0f663fd90a9eaff80326e8a67f120ae4b74a107	1608125197000000	0	2000000
13	\\x6387309471461af3a0d17abe26db377b0a57ee86ef241eba63f814fdd998f50313c00b39f36479132243b513f1d1c5788e7f43fa743227f48e3869a1f5d4cbe8	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\xa37d2e5b11dbd09a85c35a75acb7b75796c1baa06a7ec076663c53b4a1d5fdb986943cdeffde22b8c4d06d4aa7f7a5bb3664c8e2f78cde090610109c1d82fb8a6c68fbbe3d1af5b6086d3cb363deefa734619191c27f6ab54a63644407d858aebb5b633723ab81e54187fd0339d78498e843ed732a30bec071e3b7d371e25274	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xde69e14331d3cf3f1619b5508d42431f5af170eed349b81750a8dd5750bd121e10b0beb74f6db18fc359591b3d471f13d1e6b46f968610799590d8ba10d53d02	1608125197000000	0	2000000
14	\\x59bdc136f778ff78092a226e2eb88b84ad510f2008aa3c0dc953af66aeaad80e825f16556d1584b31b75352acca7e7b125f7c1f6eefc21219d561beeaad020aa	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x04dcb36c78431c19d6bea62cc8ee1f9445e90d4677cd31998cd17880cb5f5c6c0fff0596164fb2d88a5baa4f9b60240966153de00bf3222680c5428e86efdec898409e57382ffd34431538b8448e92de52f2be8bda6b977df65722ba4016de9ad15fe52adf8e6af9e247c26d461a2970efc610bdc7c3faf06ebab675af068cb7	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x5f2966c32660ffb035137dd2a0944d054ad5eb54be9ca68c581a54441bde97d9ddf5a182467fe6f6c7e8f8477e6735890f9ab1a24bcb4724c1a0099b70a93c04	1608125197000000	0	2000000
15	\\xad265ad6d7621fa3f771f6f5ab488dd94e57c7ba03e9e9b03046a1829ffb83692f1426ec4f8b41a254eb1d80582eb30487ef5c22acd0dcd2e6765e4f11ed0177	\\xfed912a8a29b8329d443e4a4212f32c0ae096b938648edd0c5ff151ec1b9a15fd26127314e904e4aba8fed84649a9b6cfdcdda6e493ac808fd9a1891ad078ab9	\\x806ce67bc77c7d73264fa5ad3b4fd9f0670cb9d53645384b4daae800cfd7c1d2fa2b92c118844d7f826dfa29e278569b0823c0e35189bf2c01624789cbe06cb984574115e27b6180d4fe10e30798f6e6074172e36b129e15511d86f4812cf2b3c77e9d13b4c0cdc7a5c72300beacecd3046790d4efdcf681c9565277c53243ae	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x17998de56bdf5d7f2bd28d2f0e5feac836ff0248b90eb92930c2a8ccca87a85f66650c4a5f2487b15ff4a3a6df8ce021bfc90101b0677b91e1cad6a4605f5508	1608125203000000	1	2000000
16	\\xd94f0cc661346b382d8fbfb968dc78cc1746789e8ffb3c5de6c79e4f7e81f74ef71c0fb0afa7f0665fe133a7440b3b69a01d200fe7514023c3c97847632f68cc	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x437c9acb22eb1ed0901b37c0f0dcedbea2ce61ca0dc3c94b4dcbc3217fef444c97881911f1683d914204ab92aac6008e94bb862daf19cd86bd248e91e3a7286a6313e3a30fdc93ee2c08cf7a0fe4cc775b26fb2f1195ae44f81e581f7712d6f277f8362bae52b2741b51ade2eccf5be41ab0137b0fb5a4c8b385a10a4aec2dc8	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xfad47986b13c95ac4623f885966f51621be3617f29a5855bfc6ec5e874846f0e760d63e9a8ea5cc7d7876cb2baecce67a85a0809171a28107896ff2ab107830d	1608125203000000	0	11000000
17	\\x7ce367d9ccdc7cfcb56eb4630ac3c0badfa0021ebe6b438db3dba2873e816cd91b08be8f9f758fd36cbed704a184fcaa3573c3ee0d4b90f110a65f9857affdcf	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x2a51ed05ec2aa49882f14ef18e23e81c047299a4683ebb00bed8119e0fd44142c8a0f78914a732af5049f7179a2d89f3cacb0ab274cc2434e551ddb72ffe66bda8e464b891993a211834390bec948a4d40b952218d0b85d13b6563a08fe4ca83ef480c9852d138fc74e36d0dde20ec2e41f94205aef30358763d3304e59ac4f8	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xe8208fbe1c99793ff735278947c826d6747b6fe5f24e0bff78e33925cccfd168b44d753b00ab62014394c29bb5816166d1197f870e18da06e46d50710c26df09	1608125203000000	0	11000000
18	\\x775d3a935190c0e0b4f063297b2e147ea8a01e36db010ef527d004475ede0be8744243aa2ea197e186d8ee444bf72c5bebe1cefd450485af83255d819d3f25dc	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x2bebc7b53dbe273f5b5b8e6a5cf63b20ee9ff8f2ec6965398ba4e0b479371c89eded8ed74ed1007b084562d2519481547fcca424fbbb3cde53f6bcdd3c1370af05fd80b9984147a9a79ee2e43ac489dde318fadafc707a5de5cfa7001faf6d4fc47f04a69e0527087936633568d295d935870fc8238495c8022fab4fef608025	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xf4add1ffffb1cd1813a8879b0e3e022b46a0e0ac7f2a37ada2a656b9ecda3ba2d6676bf47d817d8d2cacf51421b804223ebef5446680bbb07ca8ffd7f142490b	1608125203000000	0	11000000
19	\\xa6b70374fea77fead238cc6deca844c5c48cc9b8ced8d53ce6565dba4dc0328567304294389d6ed4e6ab324edc5ca81cabc69690090714d61313ccc043aafa1d	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\xa6eb0667c5e8f4f2f5d29e284eb49d69487bb7b89b808b2ff7030e33a6b686bc8bd1c5f00a816bf3bb261b90dda3a2267fb8f75f9ed130563b21dc9e10c9344f675840c14739826fa2749f21dd420b015f58bf084dc3f2634f341952e0928f237b4379eb33113d9b11ebae757aac492c63b220a83834cff00ad9342fbce92284	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x8a5199a0e2e1367db7efa619080b46ae7efb9576b06ec52ec582e2758c4d4da330b57dfe4e24074943bd771703fdd5c4082e24b43e3bd789c92fcc946f8d810a	1608125203000000	0	11000000
20	\\x177759e311b034c30d6748db43d9be04b8bb88864e4894bd36b14446f754c3326acdc589788a55edd8289671db0abad87cc5732d21995d4caeeefc91f46f5c27	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x8893f464cc1c9d2660b53400c533349f543df309bb92882e2b07cbd3b7bd8476f815482fbad31345e30db5a71c4c6ebb99a1c3ba18f11683353131bc06b1670bd1f51355b6e882bb02c4271fa86b8ca375c2432f5048b36a3aae709e26fc410e697dcc898e90ea7b7e627e51c400b3a228b0d6a595702b379812eac7d86bb144	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x5b4e54c5ecdf19927dfe1e68f46521f27229270485615aa7aff2c1235a139aa281cdc9976fe40269f5cac9216d42d0c50be94b5067e9945c950e5a190aefa20a	1608125203000000	0	11000000
21	\\x0c900a8870a64ea3d4da9b15d8cb1ffa98b857c3d9f4578e9e1181c4a685ecfc03937c2686dd1c883ef5d22ab0997636e49b88f3f3a9426f19453454dfca3ef8	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x70a25c138ae002dd79a446316fd42f77af2e7d25b8bcb02cdb365f38773d75f987608027eb78bf5db933897413a3cdc8c5d62c84dd022c4ff8ad86417b69570e060318aa077e37cb12bfa378776d69fa48e7337fa161569934ef3c17b99642229abe3b5607f7b6400743985d24845ca5592e3a417454b54de7158840f4dda678	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x07e5e13c8e120a761c748b74ee9fcf429685d4377c3899fe9ab2592be11a7cbe32521f54bebd2d4565bd48b956a4d1aaf1f252b2707b9a51c839bf8e94a24c06	1608125203000000	0	11000000
22	\\x968ef67d05f3bc3a605996891b03125ebd7957b4ea5d8e98cfd9bc4445175c16f7831b1e4f14195abc71c255e382497992042d2b92bc69cd5c987e12bcc78854	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x79b857a29860b21e1c560a17e702465ae64706358a025fa0ac6b94118e57909fb1ad68bc8dc7afe9da37f573ce8c9722db5543ca6d9c06af903f6438eb5ee3a91a432d2a83133fbb21630c9664cbd7b050763c4db3cb1692fe00e46c27db99434dc15be0af702d7132309729c1aac8ef19ccd16164ee5aab65cb475ef429c130	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xedd84e0773a5d454dc6cbcf4d034a81e493b4b0eb9f8e7b553990b5a36f590712a5fa4d12449c9a5f4aac02db267b6594ab238e9c0eefa4897bcf508ecb13d0c	1608125203000000	0	11000000
23	\\x5b7f9a40d60e2b5177f192bfcf158d4ac52e0b33de969c24bf5ea085b7a82e4d22a5009771de57e28711733dbae8ed77dfb073eb8a7852dce9811528948b4049	\\x57e61b9df24284b14e52becdd95d4c8999927bb361f80f1cb6f61dc11606d41ae458bdea4f386067ea9a09beca75980f9af68245cce70f73305bff2f4cb11894	\\x98ed44d2a1eda20458a2e058756ca779982ea490103586ff181e62cca9e3396929927e423d605d71a3778f1dc018f633507e93848a39fa5f56a19ab25d9523802caffd6e11a074c840bc992bfbda0dbfc32a9fe0239ba32c10bb076526cec2d0178e427cfc96b20ca3a8c005c9e6ea45f412dfe23aad4aefd5a32c547353772d	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x77d4896c72b0df6a61ac9bbf6a5d759f3bca608d55eba2bf4d8e2f4b94b9fbd8404a659d9ce074764b4b86baf13a7db9748aa62a9dc8ab8f4da765b5fd733207	1608125204000000	0	11000000
24	\\x519295d5d3909abb0c3eb4692df9202c660bd1bd7879282893233d4bcd3c034debb01cf548f343369895f816f35ef04d82ab6f1e5650e054c25514f57a712f08	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x044c1d60c9e86ab239e33ef5feec53a3ad539418fcf5c3a7b8de730d9b35e337c404cc3b8a684c270ca6637d8331bb9fac86b0b01aa208dd720951ddd98356b5f14b4b4e7996addf993729706cfa861bfe6efa9619ca7f19e2c3b3b3ee218a4f1578e17884956d22a6cfc9c9bf0331a5cef7a4cec7b19bf297bf17f57ad55c04	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x99d5b187fa8043e067609e5a0a37d02fa6ea215424b311c5772ecb581d44a0ba5b43990b74a89cc9a4c2da07839c8b9a748fa8257f9a800269e13946ca2efc00	1608125204000000	0	2000000
28	\\x716e2745458dc780e452ff597d25098f66035f79d4fb815f402ff6d5e4364252550b9865b8723ebe106ad996520a1fba91c83dcc9af58f9883b7f52fd6c15f48	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x6db60d269d2316c4e23abb85c6afed3d0c42b9f297200d29ccc9a8854d8df1afccaeecb38c5ffebe0f97e7df35d61524743571a2f2b9b32e4e004d7f428ec771dbb7726d77668a0de4b48bca537a8019f6bece02da3ff78b47892c784304cc8c1bd4a5b719dc02cb06b84e9f0cd613ca7b2578e5050c3d1a190246e22d3051e6	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x6b508bad76067538d60fbcc679a68e6ab741ad156a822914a8531b206c32db73db8d1010f53c882c5aa86cc59937fa572907ab71372064a6b6386f009c5e2d0c	1608125204000000	0	2000000
25	\\x5bdce9c3139a437d4b896e40e874e0f130893c6f2cd6d7b48ce7d1aef41c10a935ca971e35f67b82c897043350b1e7d37177342165d7d3d77fa5c4d518b72ef9	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x376251a9098ef3b3168e26631217b2ffdb66aaa468542af6204f10a590a530b1ab57a3a1dcaef23735cfc2ef9cff967138c9436491da69a8f3f764f9d65e77f740ea46c82bada9f13b049d3f623c0a1959251e3b4b3038ca397a7eb531c16bfdf9db259243412fae6312c071b0fcab2eb9ee0412ad2c05a1e62c158b770864d4	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x3a98f244a35c2b63fb13d4bf65f260c84cde1a729e2a7ff1bd97c442142ee53d973ad98191d50ebd87f019df4db036c4f37008b34ac9d19f92864c6715134100	1608125204000000	0	2000000
26	\\x96cdbf744395f3634fdce4b43a511700d63b941eb4385290aa7fd9079caff1e8c655aeb00768062f8f33958abe30ae0594cccb83f9b128473d706fe1d1306a0d	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x300143d5c6a4edd76bc2b8b1fc8fd38460f71166770f8f4ea2eda3f2ac0cfe644225d0a1c9af65f69ea25965417ea729bbb5966386c7198860839b38565c86e04c9769ea69ac41514da18f3e7c37d6c53fbb0e0f36eb0dfbacf4a29b71e87a1560dc0a680e1eacaf44e3f74bdcdb2e2d76e11c968d8492100009cb71649cb8f9	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\x1fac647daff3efd3ffac6aef0a8cde67d769c1044b0a204aea63605785eef9719a4866b66c3b6c78c4daa4842364340e4afeaa57e0850bf8674f6d43eee60c0c	1608125204000000	0	2000000
27	\\xb17333f782ff04cfaea0ab61149d467e6d15d44a2a8253e2a24407039a26ce60975ceb76898f6b75108c6d50300d2cb5b7bdf8ffb2ac5b9476144c9daaf1b375	\\xc4aea2c9bee33a85f96e4fb797e645814ffa26cce5ba147630caef1d066924ab72a17df2d570b83c22ff57ba1b2b3f232b20214a46f3488d3f3f651d80c5a45e	\\x0d2012c8a9ca0793a24dccf448c4912a09888e60ff1b2abd33d0815d689403c4784dbebf7932d65b5b3e184198d410f5876a430e42182538d321e7da1b6f34cb8b34d94d008256228bcce900402efe270f42e3584a87fa9a7a2b7fda2e83e12f0985bbd9be75ecdb5e352fad0073534f6dd5f787b9a747a4f2709123592f0319	\\xc7a7f5839c1f0416ba4707daa598ad8aa3c5e9245b8ed417314897c61d59fad9	\\xeeee043b341c5255cb3da9066e4a8bd4acd539b7b35bc1296210bbfd4336e2fa4e407c75419dcf7d3aa6fd9bac577409543930aad916a4997a58ce76f2b2750a	1608125204000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x559a3af7d57bd297f1be2fae769b57e46810b9a74b42f0db220109d372c7c2d38ff40e0d24ac4960c02a43ce6a216f22c4ce2fad01a4128966c4f0763d44b60d	t	1608125183000000
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
x-taler-bank	1577833200000000	1609455600000000	0	1000000	0	1000000	\\x565dfd1b65a20e31982b28b41eb7cca03414eeb185d5d3d74cdc1c866aa7dd52a1b28bea436faa112f02769efc7a77294647a3bbf4996ea2c97a22e30c730e04
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

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 9, true);


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

