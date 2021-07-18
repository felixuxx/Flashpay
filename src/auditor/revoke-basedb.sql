--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1)
-- Dumped by pg_dump version 13.3 (Debian 13.3-1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
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

SET default_table_access_method = heap;

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
-- Name: COLUMN aggregation_tracking.wtid_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_tracking.wtid_raw IS 'We first create entries in the aggregation_tracking table and then finally the wire_out entry once we know the total amount. Hence the constraint must be deferrable and we cannot use a wireout_uuid here, because we do not have it when these rows are created. Changing the logic to first INSERT a dummy row into wire_out and then UPDATEing that row in the same transaction would theoretically reduce per-deposit storage costs by 5 percent (24/~460 bytes).';


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
    known_coin_id bigint NOT NULL,
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
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    known_coin_id bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed';


--
-- Name: COLUMN recoup.reserve_out_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.reserve_out_serial_id IS 'Identifies the h_blind_ev of the recouped coin.';


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
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    known_coin_id bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: COLUMN recoup_refresh.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.rrc_serial IS 'Identifies the h_blind_ev of the recouped coin (as h_coin_ev).';


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
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    old_known_coin_id bigint NOT NULL,
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
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    rrc_serial bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


--
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


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
-- Name: COLUMN refresh_revealed_coins.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


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
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


--
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


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
-- Name: COLUMN refresh_transfer_keys.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


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
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    deposit_serial_id bigint NOT NULL,
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
-- Name: COLUMN refunds.deposit_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and known_coin_id. Multiple deposits may match a refund, this only identifies one of them.';


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
    esk_serial bigint NOT NULL,
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
-- Name: work_shards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row bigint NOT NULL,
    end_row bigint NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE work_shards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.work_shards IS 'coordinates work between multiple processes working on the same job';


--
-- Name: COLUMN work_shards.shard_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN work_shards.last_attempt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN work_shards.start_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN work_shards.end_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN work_shards.completed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.completed IS 'set to TRUE once the shard is finished by a worker';


--
-- Name: COLUMN work_shards.job_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.work_shards_shard_serial_id_seq OWNED BY public.work_shards.shard_serial_id;


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
-- Name: work_shards shard_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards ALTER COLUMN shard_serial_id SET DEFAULT nextval('public.work_shards_shard_serial_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2021-01-11 09:53:31.904146+01	grothoff	{}	{}
exchange-0002	2021-01-11 09:53:32.007044+01	grothoff	{}	{}
merchant-0001	2021-01-11 09:53:32.230025+01	grothoff	{}	{}
auditor-0001	2021-01-11 09:53:32.365843+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-11 09:53:40.66864+01	f	b3d772de-31b6-4d51-be8e-dcb968104332	11	1
2	TESTKUDOS:8	SHDKHFKPM82J0QEHMMR7HECEDGYQ4EC64ER5784PH9S3ZE2R5RPG	2021-01-11 09:53:57.886656+01	f	a614d0c0-263d-48c4-8d58-b583a087a479	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
44a2c82e-fc3c-4a03-ad94-ddd511f15e32	TESTKUDOS:8	t	t	f	SHDKHFKPM82J0QEHMMR7HECEDGYQ4EC64ER5784PH9S3ZE2R5RPG	2	11
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
1	1	189	\\x6152fc56d4910f60fcb7252e52cf9654a4fa3c9fe1ed17c0be17121914fab8d7b54258c0399cd3650ae129176436655ee8b0e719db0d85704de00eb6faa4f409
2	1	326	\\xc7c81e9a6a1724a46f24b52b0bd189f58a4ceec52c6a1cd8caedc0e9ba2765d2e3b4c0cf7bc2223f91b11e67c0d7356d9b35fdcf30c92b1976c3e219608f170b
3	1	69	\\x12bf1d5268d96b146273dfd904a12e4ffe227a567b10ab5a8fd169fd85ae6d03fd1da6c6a0e371695058b0131b23a08493d3c3fb3dcdf219349c08b1f062f703
4	1	376	\\xfc4a8ece5502863284c1a89bd0db05e412ee2d3dc16f2d667947d380b1ac0c59cb5b8e2cbee37282ed5d4c8c01b984ac6cf0fa383fafede800c27794a91f180b
5	1	361	\\x8888f8a70349a9a7a827956897e4f86aea01defe558442d8c2c404f28959ce82f780505df05f9941ea2a414ed47a8044ebb1bef0a5840b62b89c04ac8fe3dd0e
6	1	407	\\xd1618284815e773e070b070d7aeba1347c4c8c05555e12082c3aafcfc5fa46301cd382321f8afaab89e267d5959d470a7ebb2b2164f155d8fbf5199f0504040a
7	1	5	\\x4ed33a92cc877563fd4febd321d1f96210719c014d409392773a38488296d67f3b3523b8e9bde8ea52a402a058609636d2e0d90ec6a129b75745921d1603480e
8	1	390	\\xcec47baf0646c20622e445f7fc461059e37c462c037ea23efc0952f65dff5717902cd294658dc688ffcf30e9bf7689751a8237c1198c47dcb6659897e7b6f50d
9	1	237	\\x5148c08755bac89a3673c89cc33a5876335200caa889b38235512e0aa3b4b76ba3b79e80a1b2087047e64417415117620f51dbd74e2a9c6bd05a8b6dad717d0a
10	1	142	\\x19b6c60666a000d5675327459540bfd6077976918b6abcc90a8a6010e99218d4c8c37d2ba5f8cfc61f14d1978581c89f6fb8e982a3bcc0a350f794a3784e6a0b
11	1	311	\\x4a13f4f5dfb66a4bbaf7db45b8d50c1d87459a45ae1721cc025df7661b9c227bec4d7ce6ebc5c27df367c1f3172302ea2ccb42551aa5e90d2f39b58dfaef5c01
12	1	173	\\x3dfc3e955d2983c6fac1f4d2d65fac6d582ecd7fad1ba5c4ea7dd4e9f6cfd5e9ea2a99944d8c04ab1d806b83ea42927ad2d331193b7b646e9770181c85ee6b0d
13	1	338	\\x05962c54b5fa3586be60e910b6918c462051770302e3981f7815ad0a58536b072bd89f1bb50b486b7f3024fb330c03b4babcfdfd70789c312d0270409d7c0c0f
14	1	51	\\x9ceee4387c68fec8b0b0df5c12b1b209c64bcf03ca6d16ceb908ef245f33156a12c860d09ef6d4fa7e96f7a99077379558b70c14f639f164742e0c77759e1705
15	1	303	\\xd566c9ab36153c2765ab3fdf5380c5940b928a6c9c890997e3020149a9c9c66349f5c9f592dc2451eb1337ed6080dab97c88edbba60aeb160fc9782417a6500e
16	1	256	\\xb9258a9a4b6d8ff2773ff082896126f94bd393fe9243bd3a669c1c0bd166234fa60350e292152d717e63c3bf66a9cfda9a431303a6b5a778ae0d87275306ec09
17	1	58	\\xce626daf39e46065b42bbed8312bb8c6384ed7d641a3c556802d89ffb3464a43c70dab63554a6c3dd15a74fc6ce4ff9854ffe95650f532420019693e64b8750f
18	1	219	\\x5c0309e7d3ba12acf1e8f147fc20ea708a16dfefc3ab5b01ae8e0fec844768606995362ced1688839d78c9ba486de13f9e55c612121785b41e1d57a273f97209
19	1	387	\\xa658bb7d35a6f785cad483cf72e1f8f151f35dde27b661fe15ee2923d1542bd1d30114c6d6fc9a145921e07ae815790d32d9456455080c224621be3ded1bb609
20	1	368	\\x1e6efe77e99e05119314403cac18577a3b25054367ec6fc6992fcf6450b7f5a4667fe80e36bdec3c7baabda3f0e16ba7c0851e4a3415625766b91376e6955c00
21	1	339	\\x5f4d00773c16fdb9a795c7adf37a6d3c1da8ac6dc078679729c322e60c0c52633d555996b0f418fab9b6c0b94c3b129e440a2eb17011975a3e53f0fdf14f570c
22	1	263	\\xb5ed4017137312fbcef32ad0c647b31cce9b07d9f4c65031604650b7cec046bc7af4954b7105d945a859fd269deaf0ffda7054583f606fcc2bdad14d669a9800
23	1	137	\\xc1682a804aee8bca9099163216760f6416b1d402d43c8ad850614257780985112189585d41d29ee49e24ce249c750962bfcaef3c0370fbf1fa006f310f995507
24	1	388	\\x39414b025a1d768e10559c4cd12bcd263bfb42382c1b76493307eca0669d4354bdcb1fd59880c9edeeb07e92f62d650cfa7d06ad1fd1d6a4803735b0b0733101
26	1	232	\\x20a6ca23283f8fff6ef971b95b8fbea4e865b90871572f0bfc7824a3f34c316a5674dffa6e746906c33107a9c69e64ff61e16a25f3e59a59aca0cbc95d79de09
25	1	184	\\x97963c0be2b75348ba29aeee4998d6980f3b80944ef201cc071410a5a79d1e00c980a2eacb87e432b34b3b2e73b10108dedd6d2369904f1889d4c8b26d69a80e
28	1	86	\\x8aed2b95650bbdada22bad6ea2670b47cb77e4c1c1581f15e40ff022833fe88540fd1780dbf3840668b4ca130d11faf7330f16bdecf7113f1724b7b9a63a3208
27	1	346	\\x2c22bea979345fd17bed2f37f3c2f97cc3dd4fafa010f492f5ff82f6f8e0399a17e70e911b64aae9f289ce6520c5b413f1c9f1327e74ec5935507f1a72dc130b
29	1	366	\\x4fed5420ebf05272d497a6b231e7cd17f9abdc440f3cd90dcef055aad54dbf61369c27a7317b02dc2a4a2a8f748b9662b894841ff2174b1cee7a6bd54043f409
30	1	135	\\xa7c9f9a5778c05a6ca8081ff2f3c5be01ec104bac0b8d0260e2a544d3d4580685db981838b33d5a73ba17f3dd7174a8b447096c51a46b55548c3be068c7e260b
31	1	181	\\xaf31a7634cc101147a93b1cd54aab8b5cc14a3a70a0e97b27e00875451193516e46a1aa36254859fa836a9a5de464acd84281e292bb7130e00eedc6ee137cc0a
32	1	165	\\xa8ce4c1f770fdb73ed70f0fe446781d1693fd3b5b1b640c2a43d00e09c38473e26f79c7fbd6177bb58478a0104c8e8c675675496e7e9b422bbfe498af054d00a
33	1	234	\\x437005d93527c4773e3b0efb8c25da3707263d61c3f5b6101da56e75371f2a19d5fb0f2d1db4a80d7f80b6452daca8003900326147297995092cf885d6184006
34	1	335	\\x7656dfe5bdf613854c38df4b7a4c94edad831652dad5c3cf2268045d51c24d9ee5b952a978c50d9654bac924e67c8cfc4b0a36a2337bb43d52a3d36eef056609
36	1	162	\\xbaca553fb94a55d14607fdce43091c0eb845f9ee88bda95033f302d0400d401fc3bd90ea1793b75c8986800756a716d63e4691509666fecbad72e5b36e2a7f0c
35	1	396	\\xbb91a433d9bea196d78f87bb17d668eb0defcad460230c815490fdbac1adfb26851a18e7ed313b80b3ba6dad4501fdb466f5fdde3611eedc816e35975c846800
37	1	141	\\xf520882f55d083f2953cbe28f0d38586b680741c4cadae988d8b564f08556538c9a40c00a976f7c83a2304f990c2f2515639177a659f068bbcae135898bf3106
38	1	26	\\xcd21ee632c99dab5537bd6a0725f33b28d681644920b7203d5a3c89bc02f0907bb8dd5a9e26f620511d38c43b5c965c54fbb3438a56eea963841a06090702002
39	1	274	\\xc879c55fe7483b83ed79113a6ed7939d4421ef0c41bc121e17ccbe2a97633369ca1442264237f12b5dd3b5f159e556fcc88611157bdb69366bde8a72dc850205
40	1	213	\\x2e90561490a4d612164ef82c038c92fbf02339b7bc47d9fde71e30025eaa84e63c48b3640a77f5ce17d29d6dbafee45ae9f76f70d84ffc4bdcc4a1b092b2f90d
41	1	267	\\x081ef6e7b84e867faa0cb20582e834e2e4a4babc2bc59036fae5002a5dcb06ee75cf20e4f3eceb008f3774f817e8cb26ccccd111d73cd5f3be8fe5a584cf2500
42	1	277	\\xd1d38995e911bdba799c4af18af11441ba0f3a0fac1b69543aaebd4a38fa996729763c05813ea0863e3d88a1396eb75cc6a2e41b556bcbe83aba8ab63ff9230e
43	1	314	\\xb796b50a93f7673754f1cd345c515956600c14278b98a1fcddf4fb4d9981a308c093efe4d00491b55da58bd1db33e85f1c63fdb1f8164071f9f9ab841557d100
44	1	131	\\xa853201e8b647311d42b64fb100b797730a2095b0f54e8cfb560651f79424026002badd6911bc8c399c5ace061ff30f342f1abba27ddb0d72b1cb48f8746ce07
45	1	185	\\xa2694db99c4ff373641ac299fde08559272b604b3ba16a4a79f796d7f2896fae336a0bb78884b55e9c44cdf0491e6ad3e2a4814c97f43727fb6bcb627c796d0e
46	1	301	\\xee53b15e43a7c8674969b57e4de242084e7cd4a92e33a27c8a4244dc69f75a981d4922b9e71c06c5ccbb567b1dc5c30020c0bc0bf0aa2fbc60555bb1777c5200
47	1	125	\\x3ca1f57cd550c068a18db77e19a20c38c93eb6d8567c4c144282d844c98525af96523f3e0695c459102f7f1c5f9e4c6e0d77f9ed68d8bc8b1c2181ef39b57e00
48	1	63	\\x804bd89ee8202e5bb8b8aaa3a13f424d2290a1f9d34d72b7ab1ba76bb8a8f0d7240ac96a14754479bc628b09774d42e97d75058ab5580083d75143863836110e
49	1	62	\\x4fd5314ddb5d872723ff3cddbf4318734776079ccddc9147e75e281e068b7812e4c7a55ebdf654c39749c7205f5b1752a618f33b89380a7911bfe0f52fbc2a07
50	1	365	\\x2dd9b0badb558b41f8222041d4eeea2f5e07822bf117a40747941b7e362125216436c7d5938808fc70a4f4ee64b0bbc14f969b6cbe9222233d1864a35266450c
51	1	395	\\xd9c5f7b91f2e1cc2e471ee561f6fa99fdc6abb37a3dbf283ad6eafe4ef67a657125a661113a405ba6bb021cb3c2cfd299943a576bdc7d42bdb7319f58fcda40d
52	1	152	\\xf405b273241039dcc73541c8a5ff9c8460f3ef2d4a0cc8281b66409732e5da24c75e55a26fb7b64666e46def6f17f03d1d71c4b8eac825691e819f2292873c09
54	1	146	\\xa80bee15c47570126bb6d4c06ce907c34ce8f7c842d0f6b31d2f606e65badc49dad6bf04dc8d99ee58016cc9fc6027cfcdb454816485eb084206d43876343807
53	1	183	\\x9f81ed476a1e056658e093f8a1c368aa08bba87aa03778f23bfab83bd16ef682714ad873191c9053a86c0ee96101a75a1a125566abd952e0ba4a3827ca267d01
55	1	296	\\xd3cbe69a2bedc8bf04a4d889984856750081a2ed91358accccbf1fa22d6b876212e2e3850b5cfee087b3e7768dde9b8a9b29d3fc01634863499e21ded6d8190b
56	1	191	\\x2abdcf6d2bedb9104783c418dd6d1e023942d37cc0148480cb23f992a844e9bb71e1aa52c4ba62dbc6fcc16a6317cff74e6394fef63177cca55e1e5c4f773c0c
57	1	291	\\x7b14b72433ba2bb0aae9d4b6d2497a3de6e16cc69be177282d4ed280498dfdb851e053d5a260d02f08dbad3b5b5b77db26ee05b3d1af5d57aa4fb0388277fa0a
58	1	190	\\x9c46eccd85ba7385d3776d2885bde6e2acd0dfa83243c7c4f17551f927b916bf02513fc364fd1969578677feec17c7b0785bb3e2f6d9f8a7ff84c3901cf0e503
59	1	149	\\xd76773c3a17ee469763e272a3e209b23fcef221d9bd410152885baeb1adbacee218e3d35044276992f7a7012c4d381dae4031178851ed1407ebbc6802d887407
60	1	383	\\xefe3cda0bc7ce6dcdc3f40d8e5519d0335d8e0434ff80dcce4799ae12e13096ac6fe86fa1e079e47b20c72b797621caebd2f7e201211507e9efea8cef47ae30d
61	1	179	\\xa058cf30000c8e508203993488185fe4bc6d6a43f96efa6059dea600096ce7bf94ad19c3d69949c11b560fce962c19f2c6082bba184c773657fdeb1bc9856900
62	1	369	\\x1e78ed316efbae92868b4c568b98676e6325a8d9b6de63deed9cd50a7f2ad8bce99dfde89ace7266d878594e1c2169fd8068e519dca3f2b62a662f2f4b5ad501
63	1	84	\\x7d593d73d3b1f0a23c39beafd4eb13755096ec8b0f21b7e552af57355ca4b4b81446e82abe40bff0f8563a3793cf94c45fdbe4be1fdfb2cc086e288179e73905
64	1	117	\\x81e6f558dd9d26bdb7a45888ced974be9a56c24f25380aef47268e6f072bda9c76e35d4524c8d58d56e86222541e3c1f74ba5c6a8109ba5f6de574bf6a964c06
65	1	345	\\x9cc9067d337af60a7cc0a07baf173565ecd9862a9649242a6cbe235c7cb5f5251eec208dbc0140ec6019a27ece59dc9a52584bbe5023127636e9b4c82005ba03
68	1	292	\\x0c01c39b8900f7b5a9a4439a2d1b5cb3db9ddf3be8d0c2f3bf5378ae76e335492b3383d8aa5671d1563bcf97a3b4d75e8fa4de70fc845137799b076100b5ef05
72	1	42	\\x3d7b39aac852348077f3a1f506a0251c3af3c0dbe884af4ed4235438ce783a824f65357cdc0a70b28bbe42d417a61d7ebc78fe41f6486085903121a42797f40e
80	1	74	\\x7953cda414ba6063474d167762053471bd27f7a793baee712df34d0465bb152d9c6bd892e9bb7702b43da181561308677ef7b6768ea4ee0ad095fa724e38f408
83	1	182	\\x9e6f7bb14a88a03ef47b814be98832d48241009897879b2b4195c806d83f8c18f000bcd72bf19681f01f064fda73a5ba98958b2dca85102f27990eeb0f43c10b
90	1	14	\\x40a8fb44d42438269d098e8c35853dfbf8cced1ad4f8e65640703f68258ae4fc44083c4ba8d0bf0d7b77df21a4930c55b0f5af7fc29b6b5aafb559524f9a220d
98	1	201	\\x6ab3d8fb2391aedfa65cb204df46b1eede546db3a711ce7375af3b1174c54a83432577c0b469e4892f46cdb3e6f38d37a568b6a754e580356df80bafe9df3503
105	1	276	\\x023f7979c37e4c3a6b00a1e1088de2bd63deb73e782e169d9aa42f835e1692517c9d8ee03154c9783351b012c2a986d52eefaca6350b2e6e2822338193e2980b
113	1	91	\\x9f9efa73fba409c2dacc7c83ff6ce64362202d04d1df6ed10a1a6babc6d6696a8b2af301b7869412a91bd95e05153b1eab1b69ac2ede759633e2f66dbee03006
119	1	307	\\x2bc673f945e46d9f90055ac60b3daad28da111200cebb2503be60c70f61996c651220865198548f57805b1c9adb773e0a78c672806f832601456e5fa88e8b502
125	1	231	\\x9d713c3ba8a1bd6a871f9aceacae8e123bcd4bbf2679d04ce186446cb425c2ec1e536dceb60e9e75f7e8a5e6e96d2612b671c3a3bfcdcf70fb71c4a8c1a40407
131	1	413	\\xde84643a514839868e6d7cbb83d6584f66011fee52c6db5dd440655ed8060263ecbcec1e37c84ca92db37353795599f7e4741df9b5552f2bdb1fc4c60fbd9d07
138	1	285	\\xaf7c1481236f63900d1ecbfb6cd7559882b8077c5a9ed2251c469ee2a50ec340443edbbc60939a043029ce217ccbf412e4b8aae5437d05db6e87e630d5c23004
143	1	170	\\x401fe7e01d98430431abe3df7208ef553c4c52ef6dd6f709a6b2d281f23a20aef5c8969bb0ffcb3232debed27f822f66d660ccb76c70a4c9a4c42b62367f8401
182	1	233	\\x8cc2bec4badb91401f905411a18266ad9b25c575d5b8a5cd983ab5dfb5c39ebfcf78e5cf130a53da5fd09ce92f43f581cb211c9af18c95d97be21f204d9a8a0b
209	1	255	\\xb3ff9a47949b856ce06d21f1dc064a713dbc9a9b7f048098a946e75053ecfa9aa9c8728e96f3350e0f785e13e962044ff79ce36ed7743bb7358d2f336942ff0c
237	1	80	\\xe94a7bee1c1aa2019ae671a5bc12a530ddd99d9dab874ea3c7405b8ea9765d0710a8d48f2744290c066c8c6fccf13bdb9bbf7c9755a15bd1c3127349c5dae600
278	1	242	\\x000cbbe9c729a178a247a4b78291694d6e35d5d4c47ef9190171d586f22783347ecbbde6131cf701a179366a8fb1d5cb2d13bb3bc16f922ca798ad7a60e3b201
297	1	359	\\x78efa4b2aae906872d502375eff6f295b7b1960e0d6a0c41d760129951acd89f188e57683d283a0947b5cd7658de20c151396cb5a740d986c16c6d369876a10d
339	1	227	\\xf8b5b667e576786a4985cdf49f678046dd53b914a877d580ae36866316890ff91b6fbe0dea73b819b1f21f9ac61fbc35088d5c73cb819ec5d5ebe9e1f96f4909
378	1	35	\\x14dcdddb9b1591b75c9fe82f2748152513e6c26e4273dd8d62f5fd0a1f6bcfcf5121eb03a93a56be3c5b289d0d8c9fd9e8a0ed17da4c236bc43844e83e414c02
391	1	205	\\x2941aa89fff1444a6f097fc94fcf95060621a75050ce65511a703fea2a7fab8c9523923c4c603f8765b7a51a72cd99b1e782fd6a8bd8169a314faeac1d3c040e
69	1	15	\\xc7ec6a10e107920f229327753ca238810328dd1061a43e365e6dcc98e2db66bb4071401721ceaa8a1622267a1d1040fd60c7a44944da2f27543da57d3e5fe203
74	1	200	\\x2490f684dc3c551c9984dc6d0764b9443a25c6f059952834924de40735ff087aa80368f9171dc96f902bd6b78f2dae794787d9220b03668a650b6c8d995b4a0e
82	1	54	\\xd8dfb6049984307cf1b59c55a04a79a0130d2e378dcce7a683ce33e9e31bcb1337373ab98ec485c98ea076364c0f6e47536832b2543e4dd570f7157991900c04
85	1	329	\\x80524274e1e6ee682ff9027864b569e183414e1a55db705ced06fd1508ec17c0da03356ecfc17c8cebf288dc869841323d827ac7b10ea81fb4a94df4af3bfb08
96	1	120	\\xe6bf0f47e3ec045aab95cb6f6a8f9819071c009ae2803ba77bb582a1d487ddd46b89563ca65eeaa645caf88fb734c48884f64680a34894afb02a0653f701f408
104	1	100	\\x55b029bb560643f2ae3130e042b48d48fb7147a967b54892cc79af7b4017e9f4d16541b73781cee96e1e233c2900854ebc743531f12bcefbc741eab6a82c3e06
110	1	357	\\x9e6939d75a1717c36d9471404ebf9a22eb07728c5523bf8db380f1d2dec70ac9833011e4204d3be902c867074862f6c081acdd3d05924feaa56ceaf6ee58a40e
116	1	105	\\x879003b831c31b42f72b3bfbc5eb69b04624520b205d90fa48635086cc96d6599342f0e96755fac150c0a04e96f33dd078200f8a05655136d430702fef3b3905
124	1	150	\\x12785435952374f8ec2fddfa77fe2534be4b3d7eeca8742637a5c278b15f89c2f3b69ac3531eafeefeba71bbc4c591f0aa9997128c295f28dba716711359580c
133	1	13	\\x43aa7cacc80ceedbc0b4a01bd74181f73e9beb0cee0ae38db112c9ded18cd123acb710c55b47781b73e96749e3815befb65066cb7cfbc61137b130d0f8e6a006
140	1	230	\\x68ee17dc53207a633fa5f07510b3ab112b7750b7b4d044f719791d02da39edf4e34480d390d2ab5120754a88ea818288ae2b736e463f7fa6f1725873d3f69500
193	1	254	\\x0d67b8961e5029c571eab1eeb7a6086ef7316e22961abce4c7b6b812abe4a8ab1dc9a16483bf84b498c624d3daec6e54717bafe716945d1b31db0929f79cd20e
213	1	83	\\xebb693f4bfc93b58f0681a97bfde6349fb661b2664262c0efd1d4e3f0a9dc1759abe8e43b436948c17d19a37d68b6f845d63f577e558550962baf317adb5fb0c
239	1	283	\\x78ad55fdacaa0e627a6bf70e36566d74114eb6576f872b37660f2ec713bcc2f5c2dda9d96ba313ff799b4470ecd110bd7c10e606a936da5e4005532117fa2208
301	1	194	\\xe8a9e16ce7cd9f555871c28c513a040ba76472675528c79fe9fde9e49638d15681dbd33e7bf5d6693e7ec3693d5f9afced2f8af97b05d034c7ba84dd76f0cb01
328	1	386	\\x0af817c00693508409aedc5091e1ef85844912d05cf84fb590918ea86d1cc3148068e9ed35100a5e3c98646a389de5332375513306b03f5df53097ae96b7890a
361	1	160	\\xe8bab6c185f1342e77bfcd99b8544f6b588e382b1e331f85e0a86707f7f38296aae4cf0d7d1821897dcd13164baf8bef871ac1ab9d705ab32e80515e95195803
373	1	9	\\xd4dd803f47a7c730a1a34b757126de1bb07727af4479079664f44d66d5d7ba13c973c49e5ae212b5609473633f08ea49564c3d577ee17b5477e5459cae5f8c0a
401	1	79	\\x5a6430340735734ce452710f902ee050cda6a174fdfb5f35d8cf81b98ae291f0174863cdba1ee0d53d9e2e98b7c2384d77573ae3f16947c04b6496caac80390f
422	1	20	\\xd06781a2772b52a32b6ba650412db031ab2b4331a78f4f72660f5b55b4cb197be33a606471693cfefd6e741c805d4550d4d2f41467caa5d4712e93b515ca4b0c
67	1	167	\\x08d0ddcc63b77d16af30dca218aed740247d54284a6601233a2b19a274d2f0034af02b264e44f8e4f11f075f7d9fa845a9826efeda6204c397f9e1e8671a0604
77	1	145	\\xa57508f20ff5659eedbdcdc3333c92f9ebe4b4266b090ae985b054e00696f6495470b3a2af13982f5b98c267d644df24394791803e574f74dd0a5a7c74d2c60b
87	1	415	\\xfbb43bbb5365b9941e7d7b9d6d42445eee9092e1af38608913677204740719bb014bc0e53cef9a441d96208f2ea2563d16a992f216a78bacde18d3ddc904520d
95	1	31	\\x8a468db2a0c7ef25ded907878f4669d02b8dc344ee641c43631799c283beea6b8a566a3b201a3eef663e2cf2726fb7186208946c2613c84e5e8bbc1fae32430e
101	1	252	\\xa6f8b57fd380023c6f5518a7dc0934188bdaf957bc26ba7e64adec3e1a420368f8c304ea322ed810fe71cacc82b77f0e3caef43b7e3dbe8ab03ac81ed400f20d
107	1	110	\\x044f747c69e0f49bf7a38409b5a168b459b8a3267812b50b75da27a1deef915f767b21468def491df71f0e5c85a1851cbc0fd1d65ce4e2c69cb67fbf16a7030a
114	1	101	\\xdf6b5a6f97f274aaaef54bd8d2b36934310bb4c76bda976650e785e4d3b1e1d7108962abb438bc473ff5ab3533cbaa44cfaa858c6a35db52eb3598b51bd01005
122	1	106	\\xa426be53b673a36ffe4bc517a9ca673591df64bd384bde95278b9f626bd10ee1af32c6f8eb79a00eb5991736d93bf7697254c4145b47f349456cad31fa48350b
129	1	48	\\x6d64fc0558d10cef2a1d7af8d954be9c2f6a517c5903631690b12b543cade7d2a791eb2ded5b8744f63ad223fd7ab462b82f3fc9c85dfb0807a9b868b1c8160d
136	1	398	\\x500c7f0cbf2737bb6b64847d3e4df99ac56fa6b70305b67d8e3fc9ad685d899c8d580e41e1455e7e8633bf9f501b9cc517d81e88490a8987c7dc3a506bc0030c
142	1	67	\\x500c10388a15cb98b0c6f924d6e4c9283058d083881583d1302416217cce55a05ff5bac7091fb0bf873a448d77254afacfba670e1e42221c61763aec3d7c0901
202	1	350	\\x61d41b1f51f268b274e0bc2b69606bfc1f6fe40d5d7dea8f43a43af96cfd7c02254b9f7017e69d654145227236537d1eaecd665dd0ac4fdb04c9a94321982b02
214	1	258	\\x56018dc19f7cc8718fa4f4ff4c2daa5aebf3d97944f9ed2fc982e7560d9e7259fe4e4070bbd7142cf2a208bcd66575ef7fe0534dbe9b6f1a65aa9fbd5f53d405
242	1	377	\\xd7eee56cd4ec8365a9a8e855be3fba32799d5f0fbb0d944423843fb7ffdede1cd9f44891c412b41d814068a6f679a17b9d23b07de897f747b85fbb7cab03550f
317	1	239	\\x730da7dff4b5f4b72aeec811008342e00d2e57b345039df6db7d32e0faf25927b115ea7ee4f5ba8be4339c6deabcd09303b3f960bb1ffb19d7fcb8a004fe3d0e
362	1	148	\\x78117f2bcfe3a1f26ee1844a22b1a603b2148b136b6e6b8f6e924c4a772e3849a56bfd0412ed0b732e08148fc2dc0930493fec750e0eb09da0c0382a4aa5fd09
70	1	221	\\xd3144809f858fcc72f2275153b8c6fcbfac5f884a9da69f722327aaba90bd74c5632535a641e1e5b8d4997fef6f995626e03810d5327dc6723af43dca35cbd06
75	1	312	\\x1abac84fadceda8511229f6a407b5c961c713b2e407a7cf2196533f894d27a98599be4145e2b394f88c2fe43cc1ccb140b4ffba2eb44dd719764f2b91e14a002
89	1	412	\\xf7d1fca100286ab86e031d4d92e3e6b48b35fbac3392e72783f4704ce93c0c85603a85b5564e4a7a00f8ac7d79c4abfb1038ac1806fdedb2d24a049f9c3a3306
94	1	147	\\x56b16dce1f13d46a0145b8b1a70c8c7683052160f0928485c729cf3452788d2db501b72f23702dbfae8a50a29d27fdfff01c8365c33835c240611b99d89aee04
100	1	268	\\xbee5e1416bb5d3a93ab58e03e8b509ae9b2b416425d4b73d494f4fa75b54edac8239cbe3f5aaa3154408b9dcb094ebf26e3cf3440e1783d1e0a8a89479d7fd0c
109	1	154	\\x3f8d2cc08bd14f27e9f98d705d4cf52547e93d20bc6085acf4641af216fb7a3df434a3b9a925b599a2777c7358b93187981700ce88f96357f886f52c512c380f
117	1	98	\\x28fe68a9ddb4fbc5d72412540f361b8359889284b94465ba39376118a4009a0b91ef57dd10453f64ffd9dde283717555c194c071bd22472da786e84aea47cc0e
123	1	169	\\x798db82203a4805fc7723409a010136b81660274fba0b1f82e3b70f6fc07429181a326c3a048af6e34422b16d31c69d39527b47e67ca8b4e11d9f63b440f9b0d
132	1	108	\\x30e6cba8729604ee49368889b4d9d204b56d7438013db9126b47733076cb9bde8db7426d836e9e8dd508eb80c58fd76a065b51ae5b7eb40cc81f5b7d72ca3b0d
139	1	59	\\xf21f64b348a8bcd828ad7f828260d4c010d24377c50f3011653d2cd3b017a5ddfa0e83081b8468eb197527fec81484532efea01ec9da359accd0f26a31d6730c
179	1	132	\\xdc96d5db3b12f269986ec5172e5380747496895b80485bee578d108ab95b4e74f7686bdf4f721349af5e4074ddd61b18229b632cd021855f352e52e52c9d960d
212	1	61	\\x4c9757e5fcfcdb40bcb11397e9352c70ffabcfcb61a77e1b61e85e9d60d34a57dda13d535479cb028fcaf4cc7ce028d87718fd43a13f24145c383857e9c47902
244	1	382	\\x8bc137c2a082411c06a244e0ac77d453f3ad0a71edc36ee3417f68743993568d45602c3b0bfbfd93099f163219506ed07d55d243c1829d096b94b1fa276fb201
304	1	71	\\xd2f9527086b2d028e84a5b5c08b74eb770e4feb52426520f1d93dc1f8d40bd2a8b62f4687bd4c34a99c97bca2a07a17d0b1a2af24aa959c490c4ecbe0fc6ba0a
342	1	96	\\x3b0db1d2cb786848330b8d396988d4d743f2774fe292d05263083d1831feb45c5343d2b40db536c2ae4ec43dc4f87c59d5afe1606f0d4de19d606e729608e605
411	1	193	\\x989e58ebfe662871950704b718a2423774cdc56ae8198b2d67272c0cd7a10047e54dddc40925131b787e482f2b984ee51b12eed2411fcf7d13f94400be74fa01
71	1	226	\\x2907412adfb7d22608a813588ad78d9931d943d25e79b90a6b1787bb6c4dc186f973c9595560caf8ca3202d23b5a3379426375a0d878c616e7167623fd0da904
76	1	21	\\xf9cd9eb6695424af20e70b445d20a28a90b277e69f55c2a6deb31a80e8f0efdde8b66bd7d5e3eac66f1b1adeaae4ff95562bfbda93e3109bf5f670ee3d719808
81	1	180	\\xf8ff8f5ec7fd40f445ea8d45540d53808e8fa6f278c6b17a223f95dc3a771dc4775f40c0f4596af0b228e5b0eec3904ab1132e97853106157b42b1fb1f4c840b
88	1	337	\\xf0dec328840ad3f1f3c82d918f4e759913f2ee0180f220e8735ac98b2d195cf1f9e02e7bf56dd9dea2c906c13342115066c794cadb248ac99459454de8a44e08
93	1	114	\\x7c30b1b302831a44648953e07f2a6864eba4501cceab6a1080c5b3cca40e2b3a00648faeff549471b50c529519846acf8c39ed785a2bd9167b9ed892a811f50d
99	1	208	\\x824fad4694f95da5b5495399ed90ba57e962d95cf0eeb41a3a49c139842a94947a8e2b4ac365e3151b7d0156de5f0b929c78f590ac1e03599664a7fc81ace70a
106	1	225	\\x25a83339536c7f7b6b4bea291012873b3e54cf1cc82cba3245360ecda5ca2bccc740d4c7a439bf90c5a3dad3d1aaee278682a3d6c1cfbac3eee2d1a07bc13b0f
112	1	380	\\x77214b9b57cc7f3c46e88a2e3e92dea2d2bdfed12f46bf68231dc5a9cff3ff561300a0c34fb7212e481135a7f316b42147e045bd1d6734882d09c1d68186df08
120	1	244	\\xd776fc99f4eb96f42fb80c60f06a0dbb1d45e96d339d3b97830ca6fa4f9df2662c9fc0456769ad6745e132baecd70c8f7ef1276907779ccc56cdc87881ba9e06
126	1	212	\\xecddaa0c8a238ff0b14c4c1fd2a532c5735c8655c6ea78db54992680bf8c70f25324e4ed332098b358f683c580f35a1db2967c8779e646d35d3c1469b9343502
134	1	358	\\x997e5c549cfe759d7cfecc1eb8851ee6b3369c07e1eb901cb4f045c09ac4b56d3cedb68fe4120b4148f03878b9e800c54d64e56fe45c8005a4341b456bbc7b01
174	1	309	\\x77420117da36dc3d8bc617ffb8fa4336176f78534cbf8ee5c3eda983822bbb0f290d75cb80735e234a20b0a0e144bf06b82ca24a76984e9006459a994c15770a
217	1	159	\\xc02eb7005b6297e93444f57a5adad4d2705888d8fb458bb31915b358ce1a2e422864a95a979356606cb0eabe69db452ffc6cad16a9f5ec973368744a25730a0c
246	1	129	\\xd0556f6deb567325bbb1d435034dd2663e5e8e19b6cab96a680a3ef8af3e7aa1d767461e4d45709a59b12e945d98232eb118fdb423a5472e43d80e591b1f370e
320	1	155	\\x18abca8a84c38eeff4a3dd758a8fc7ce78e6cbd18e01b5e71cd939900b208ca5192098f18c844df85868a868a46d983cfa7361965b5e8d69a132875829c5100f
330	1	403	\\xce1417aba806115919a535454a4d31bee8bc061c94c6009326e3ee36d8719607a44f5c58a0cdc39dcf5353eec8d0d937d769d8304a10a7f99a419f732c0c360f
360	1	298	\\x9e4e32a81a352dca77fcad68bbc68c1c1e696af551ff4a3c0ca0addddb2538db5e777e6154097f832a739288440b7882afb2145458cc5b8e89e66f386bf62c07
415	1	214	\\xca7349274ed971377f4047e652907eeef65938f3f630af5e503d406e077cba1d7c3da453e8192af6c1ca86671b1012aa16a2256f33b941dc95b73e98d2e8e50c
78	1	324	\\x6efee71d35fb7d08e6f1852e2f1c58540e2766eab95ce63bb64436fb9547af76628b340e6f8719204c14ce9696309eeaacf529aaae894cf886a14e204d0f9802
84	1	299	\\x800e8a43ac84d334d686bf3439f14043ef6936e05be05697a0d66d1a74fec46de5b8b2229873930df2b99bcad092134c42dc9ca89c78bd777365508fd2ed7b00
91	1	211	\\xe8c0f6a099142cfddaedba8bb3716349c0bda687b9257de41bdbd0237ffa042c166bb84b27ec83d7e70c3dcac2466342784afa00247b0bb6a38dae24500b250e
97	1	4	\\xc11a3c5360335d3cb555f0a22faafec1f45f97523a52edc723c3844bd534d65a3e624f64e35e2a060b4f3f81620d7f74aba8ddf37f2291f4662c7383f30efd0a
102	1	261	\\xd3ff6f479bbe9c4dd2230e8c335d114046f5d2df7c78022a6b5c5984e278541217686c3a14c4ca0a3ec2cfdd7198a23848d38a979dc14882ce3eca841411990a
108	1	229	\\xd681e8c38305e65124a95721befee39caa8ed038b5f83a9c8cb97c055ca7b3fa520301487acb8dc7286db579ccfba9ce9c8d89ba7aa3d087252621916152f506
115	1	40	\\xa6c154c9a5b424a306dd4e30839553595b537c1cdf201899fce26da2fc77f3cade5856c9e77e77ca7af205eeb5b9808d15fc47878df072706cfc0b88c3090d0f
127	1	157	\\x492643ff62dd2166257397d6f85e95c5ecf2867a810d399bad0161206ad36631eb1da9b0ef3d32a9621c45b603432efdb544b56d3f0f12f35a6aeb3dbed05b0b
130	1	93	\\x5c7cfb156fd308c86484bf54f8fe0369fe47e8f8169ee4d0759ef1a924a10de5b8ed29feb38e96ec670cc0ff46404c62680446ba7b6ae38fb73faf2a5cfe520d
137	1	25	\\x6d6c7a5058e95312df6bdd584c28bbc88069c020e86cb20bf7c161ae922b1154fbd48d131ea6f9bb60f4a9fff1e141ba66af4cd736a729c70a65e84a19a27104
169	1	317	\\xe319d8b20dda72554d810e7654405c65581d09f97b31c80bd56779ea5228516b3ea924957eb0be8922c1d5fe0042ebe1e516a38a71185b41d23972de7f785a0a
181	1	75	\\x6a872bbf1f7edab019a525ca16786c3928738409952fb1005acbe2dbec1245216b1f858ee2a1b7e94519a71e9f3a6caec5d4dca402fc9e2c3989d56c9df9b102
206	1	112	\\x9bbd20754ef0517a7b0b2f7a6672370f326e00edcfe50a56d39e0f8b29a82b4ad85c35093858a1145824386c3198f9149df771457ce586c05a4734668bd2f604
222	1	238	\\x3d096e5758e8eb5015f28fa74fb164d9de9ae45ad48625360b7c916cf0848efe8c77058a2df8cdd42c1468038c7be049d56aa6aeeba3854f4023c757713f2507
255	1	341	\\xf83580be47c6b0d00508e94d572264cd0694aa9f053238f8d50bf7198cac3584c34092fb274a47057d71f3f3c1778d62524ab7ee00ef018a35e30ce5c7f5da04
288	1	371	\\xaaec55babff437a3cece5d4cea2fc49c83037423e0739e80bf6774366b25dd9d3b7bf083ae5fe11b5c79b025a4dce3bb0c34eeccd549e1ab1815e5d0b5eeeb02
336	1	334	\\x306db11468de54459adea25b071a765bf680002db0396f066107d6ffb3cd6accf6d4c83a713cd1a5d03e1a41944905dbc7c4e66fc637219ef9e6b51316b4e90e
365	1	409	\\x85e35d5be3986e6be74745c618d0fbbb6f4b5f44c5b1635a1fd7e76b7c5082a66d27d93b8723d63e0ba6f8c705f29e796a73e6d201a62ad6bdb08cf8d96e1d01
144	1	85	\\x42f1d295b7765f9fa74d65c599b4021154d9a3d3aff822bd573bbac9d530485e821ce19cf16d8a63ee85266dacb5adb2b8b3544dcfcebbd36a89f6580f0a0902
195	1	187	\\x8dc5cabe9ba0b4a487c34b271fdcb0706f31dd34b3e3c6477a9514fa73b0ed70399bc7b9f285bfa2a9f61ca1f51889b3cb6e198394354be7d0d60c6709da9e07
232	1	280	\\xbd1249e00f7110a717b498cbee161a77e9276acecb90dcbec95f063a02f37ba192a652e5743af9889ee67d84beee5cbf687066fa5b7c886e6d201b6e6f4c2e0c
267	1	99	\\xa0849ef719bba058a33d74bb4223d5e6a49e3fff4950d8d86037fa3a9ac3bc6939c00459f660e71b3e2967457f78a450cd94916a8a8319f4392314d6e037f10a
284	1	222	\\xa76a052926be10cbce9f55a58fc3fc753f4387ead32b73eb7066b01bb0f6aeb588df6e16e8e5366f2a52ac6cf34ab1fe46ae1a9a04af4928194c8434d481450a
305	1	144	\\x2c22a3b4f45ba07ef547a0925adc7c6b275ac8b1f2605f0dc50b2288d686fc0a07a41e36a22b0b4f1a9334a161700f3b5c1642318502599f88a4851076509909
319	1	57	\\x9d82456a349bc9c5bb8d6eb48cdf25166fbc21529d415974cd0539a8a447a4a4378036f31f3c44c30405a17ad86f64d7cb38f19ac96953bd965772a5264dc801
395	1	143	\\xd2735238da10ecd083e3daab66d2273f552520201e34d631684b4a75c59d3e0020e1895ace06924f3ade877d4fd6b6482db69ffc3f4d533120ae06a2ee90530f
407	1	82	\\x5e367d9a9f343b4ba1db706cdfd094e28bf47258a058d9b91bcb800a771d474f8cbd0535eaa2a0115b4ba0c0cb174a7dca1bfa105dd5300585c6e1bd201e3203
145	1	176	\\x691df54f439de6a4b049b5eb1ad4badc16143169703411e7057809e1f8a27393f3526473183954ac9fb795463d107bfaf13927760cbd15c120fdcb9cb8892b00
199	1	139	\\xe93b7291564c335079784ee858747cc62b52e7a97eee2e1f8013060fc50c7ada3564732ff5e7968635cb7b982be92cfb70c1201b345a8a67160905d97e64fa02
240	1	297	\\x31f64b3a89899a5e05467d30c038f70dbaa5a95d90002388f76b0afb6e1bb3474b45bda3c2733d39c7d8a0d9ef904f8ccdbfb0d7bd61c572cabcf9e9d7f64f0a
268	1	385	\\xcc752dd33c921a74fc847ac4d236ee0f702d1224f8958262b81c3a8866c5522977f7643489f641a79b5a06856e24d0d8a6c2cac2b99ae81e75838021f5103a0c
302	1	78	\\x98b85041542b46081a37b46cba93c1807d853417bf715254928178e369bfbeccf3d3f4f371d464e5cdcabf95f4bf8a760faf057c9e86a0ee571e33eb6480fb0a
331	1	372	\\x1cfc820e6af34290a92aa6e7755c7fffb79f23a9a0108b253d579a694ac92e43f1991bbb79e88616cfd3dc5360c03635050ea68e050a301a879c032358f3df08
355	1	44	\\x30973b559a6acc8be20abdfb90f945a3ff18eca7fececb65f688fdf7ab1b305434ab399810359c657608f2d824b8bc2fb347506619585ed43494a5c984815609
366	1	318	\\x8bf28415ce05b0b752b82c1cb2c76e9bd2511fe6d557a638be7a82adc119484eaa0496b5ee0dc4e069a053b40f85127d3693b6650eb0c306aff42512220b8803
403	1	322	\\xd5cec0f4007067969ecce579eb1f9aee8c16f98a8c0a42e8eddae61aafdf4b918e33b198539578d658c8e149190a5791237fbba3d8a015bdc4794ebcc9312302
146	1	87	\\x5996c28a2c8e721d63d643e1e585e5fbc1f0495caa530b716bc39ffa309d4924338e736e541adef7ca65898bba7cd81994a53b090633c47e907cfc464db4ae0a
196	1	308	\\x3e4a9257668002f277c18fa2d09c83d6e1f90715843322da24001b5fb3ee1adb62b01a3a47f3e980c607dff2b041cf59b2c8e8bb4baf6c84a638aed74ef4be01
241	1	321	\\x4d74bf76685da9a18dbc52d3379a134edef83636292122bb48e7353b574f7c50e07ff0e8fb1c8270974793273fee1ceea8d6031c7d4ce996fbdd7a295372e50a
264	1	128	\\x1caec2440d927c74c69e9ae8a4225d253d345c9de4bba39f8f6afb0c7aff4e1c6d21840def439919782c2728bd2e93515d556fee4ec296147bdaf8fd8ca48400
315	1	286	\\x5bc2dc9d9623a2fcd0a97dba5085c15a2a0262a41281fd6c9eea03c42c28e7c8c3574bbad3c55d425bc531f87184a8320ecd8c6b26aa8c12cde978f7f0e01100
341	1	153	\\x5e6fa237d2a919e039537a7fc9418b0bb9967a192c45c41ade0a4a66d413e66fdfbd7bfda36230637365ab2b06349db1de761c9feaeb2d84062b43c24edd4b0b
372	1	347	\\x080aeb7368a27b04e26bd274ec2eb82b0b47c7027e1a88ae64ec78441eb534fd25524a5d44b21db57b9bae7e40a7465c420996e58f3778e9821f0a05fdd2250a
386	1	370	\\x4006eae04b960edabc5493e8062046bc67f99d66c2fdfaff056fbc54ae197292eb3ba453a1637e083d6a7232f749a1e7d82e0e777fd09705c86be213cf1d2607
147	1	136	\\xd67c623df53a1b31dd57b328bf254fea2f66293c33f2ca5ca288ffc6487edfb207ed85733ea53aec53f0b0a326a226ab48ac162f59a6ef29c8807e9001a18f06
188	1	68	\\x4d5d9114f08ec62c09fca4f9640c8b06018b70ec3a5cff1665580fd3719c3a941946c11ba9a6c54df736b2c6f3264121dc9c1491f977168dba123899aea7b700
218	1	220	\\x69480edce4da81bd8c5333c06332a2f9d2a1f90f1031504e14323ed6cee13bac86f67fc3e169bb537a1bb5e96b17f1f41b18617a3ea6a7b4b1c8d47953887e04
249	1	186	\\xb5e6836a514d92bbfc4236eb675f78734360fb4fe997294f0d9d44206b5e73a2bc2e3ce92dd2e716378130657f2b1fa1395231b339a10351d996d7ca8365ff0f
274	1	95	\\x5d213d607780a8d701bf77531cb9b5e37170fc1d39e49a9e06e662d5faf515bd3c97ffdbf0f8aec5b6979f40d5c69a0356faa5812a580fb0941b8723d0baab09
292	1	29	\\x9c997f8f864f80a8063e25a3156788fdd00e95b8b60b89adc2db1a97d0acc7829e9dbca71b5551bf79230b3a4ac99cd4d490de1ff4e9319c84e8583da7d6e701
309	1	414	\\x4fbabb61728a5cad036dfe76d8d904a187070c328d80dd50cc382b8f728d76d75de9783d741923cf0dc7ea6e374c1e03cbd8155bc73484e6788f38f8bd6cc106
334	1	248	\\xd3dd69c4fd2dbbb6af4eb684c0eb6368c38a1c93bdac0a6447bcf8f9c301aec9d2d3503b6c37dc71f4dd6f01998fc4d048e413d5bb05a36e0b9abda8d059490d
148	1	328	\\x7a49926a8a91565509e032b94169d66046c2c17151ea9bc91ea8daa09a715e6ace531674fe34064503956c82c04065d1234e0e2a18f60459a5cee223344cbf05
189	1	10	\\x0e77be888bfe59f2570ca231c40e1787774940dd9c201997fb6a063e2e19f0e9ff6d81ba9f7a31257b86c0a8800bd237fa22f68febeeed31a1f790050597f903
225	1	188	\\xec9dd6ee1418e3e79e91c2545b577c910842b61c483d93fdfbbe83bbad060a3e491c1b9b30912f71313af869c2cb43923ebd7f843b5a65cd4ddad90f46753c0f
258	1	177	\\x05ed142811632ff2a597495526b271aa493260e5d974d79b0d5633e8a4529b090a5ec69acaf7b5956690edeb90312b5ca197043dc533d0d52b2727d4bbc3b40c
298	1	402	\\x7943c3e6787362f4abcff5d468cd2d3fe6d45352b11222f625555b6f2fa4a1d2955defa832d363de7f2a71140e4f89cd0aad6755748df35ad5ef0dd55aacb20a
322	1	331	\\xe02827855cedd115d666878b1f0166e83cd5e84efa1791b63f45203857a13610b761724d9302d916b987989e3efce6bd15e225bbeb749c0e520ab2c6a7a5110b
338	1	273	\\x76e6856049ff12093305e54cf3b246f8e2682b98a24b2b6416d4bc18f463186009c3f803fe807dc94c30b32bdbe4d53ca876aeea52c9345a025a28010b339a01
359	1	64	\\x49a30469071869850fbc77dbcb2e867de1b3697988e823a3ba5b6ca249ed6baa8c72894042e1aab8f9d08d74c53a9f90db1786afde06e94f76b9f812d72f6900
369	1	158	\\x990cf403e56b63902f5d028173e8d7e41d742989563ba01187be77055332c14e7a34b7b4ffb931bd88c7007020aff9b07fa0b5fda3ab610c6a39e1c07a352b00
388	1	204	\\xd193bce368e44fdcce1fcb217926d8257935f8f79e6dd24aef2e7a5f471e6af8e846ac840b2796a31c2afb048aa8a54d74fc1a4e6531374dc1c4759cb9154a08
400	1	218	\\xb834c171c4fea3894ff1fad1740f111f9a8a7940c1b75197fbccf619e1cd7c4fc7a929119c89691fd08bfd84585602899a4d03a54c50842371a11d7e1ce0490b
412	1	174	\\xee011150a734a554f8d4b5f4017689cce4c01422d7467839c9971a2a18373b655da700dae9d085810ad1058501a7de27e60132e6fbdfd969b71996b6f949300a
149	1	216	\\xfd0d9ca81d15cf16840f3b87f483aa3651dbd5e51cea44e7204474c97b9a3b52acadd971dc3a2280d9886711bb0469ebb6b4d57259524b0a640f617eb379b208
177	1	90	\\x937ed457ab69a94dbe7ccf10877a3a0097a7b0edb5f444193332c2a75cc24977c17bfc9c3da5edc0241e705e63c99f9b021bb686208eb12e48ed7c7f7081dc06
204	1	8	\\xd33cc91232e91dd3236f9ffdd309a205eb85c1866f96203390d59f7e5a6a9b06b61261efc5403c2f75a66cc1262bdd9536c3dcf53a07417af1840efb6d77a206
234	1	70	\\x0462c6a8ecc2059c2b80c1742f138731e76d5c735f82189c51bb913e385bb1b77ace89ce05fdf9d5b07986d165079680866bb872310ade4ef1970eb702a46c08
261	1	140	\\x013ab08009f7900bb3a6ec2ebb9b549df3fb86d043186476b0e6e14bb0d565113aa10f70345799e61c45a47664e0e45dbea21f18d3e07214fba45a779298040a
281	1	304	\\x2bb92e04f94df5c4031f3f5c544a2d990566e11e9f2342f2f4e07144b2e122f85755e887c1481a630a216b1c356397c6535fb537b55d06b9b0421a8c1a606e0c
307	1	249	\\xdf3a3f3e25dd9b3b814f214b4cc685a3ada57f6be3319801752b1563a8569ae12adb96deed0c357be3ad407dcb675f211d2a07c7ed7d744ce52aeb1510d6770a
324	1	360	\\xe58cf913f005983820beda8b3013839bc333d3668fb3f8902b008b1b02168608baed2776243bfd72c378d2cfc3017acc5c98813e9432911b193ccd3f70337308
344	1	37	\\x94ba091b64ccdafe93df519356c2591d179b21cecc3e9587a06cffcdebfdbc89447bef40e4a9932deadc2d5288a45e33baaa2ff0b79fc68a52e294163327980c
150	1	33	\\x6b2a55b8fc2c763048afe7f0d629cc2bd6c4e49679898a48d2486adcff4047cad332e5485528e7ed9e6b1cc2b1e87546db29c379b266e1faefcf1529cb6a2d05
194	1	38	\\xd6bed6756a9dd409ce9f3008550f14c076685d8fbbf96e64335b9b9fbc342518b1d92eaa74c8d0343ff544d2f26095b2c2617792f367ac9f008d0ddbf6aeca0f
221	1	284	\\x4ca37beecc996562506679a2071d95eef48ecc05f9e6a30d98536f816ff8e9f0704036a685389a2de1b8a46b2444328f05711771484cc33578dee28e8b44780c
256	1	109	\\x73c2b46ac722d01b7d87a8a0db1e3b111bb9a992a57ed2d80bdb7a11302e209f12580203474d86a515d432cd59c3f51b68c246f32f67c90c2ce8f4543c0fae0b
286	1	23	\\xd592cc94506fd4a0d0966801897b2c3e1a9f9f3606e7cc6d0bfbd685c82d9c8ac38524b95dbcf2d59318a9e4cd319991300a9ec5668c488e1b56b8440a3ca80e
308	1	192	\\xcc19c49d942c4d2cc252dc0126cde3ffe5ca2b34a9899f39c41cb36eb5a3d7f5f28588d3bea93b251c85c0e0ccd60f28b824d017a817e72b94eb60a0bcd58d05
332	1	281	\\x7b8b134cd3c4d837a777c9eb22b240177491e9a16228524126ea68f39cfd21516274f54f2513bc8374fc3d7ead57c582c56a375498d5e92118af31613b9f7309
376	1	124	\\xa9aed5348b4a9558b78be124392d9d26d955947c7fdaf278463c21110008783f75f69a0f45c288aae6238efe88b3304873fc060eb4340586ef678712f43dec09
397	1	111	\\x9d75471127722a5bb83137bd19eae46245913dc6c2ffa6c34a8eac9053a2db346ec1cbc2b3a54da88c18ad9009393a15caef8185fa879efef9332e1afc589702
151	1	323	\\xf669145b6c007eda2c425e9005becc352de15c8532598072745981e9141191a1c2992053b8ba734b9c3501a2f00edf17175d5614d53978bce6be4e738c187206
186	1	47	\\x318d6489ff472f4153356209a853295a10fb7da42013e291f018ebf0e57f12bff163ae786a206ccad7f4e43396422e9572c605782ebca7b33f1541f5554bf60a
215	1	270	\\x785465b24387bfefe60206656e2d6933fcfbdc0fbaa51d35767aae14f8a3ed5e0978a11496e896e6183c1120dd6428e52557befe21a9508b8190f08db041d20f
245	1	134	\\x0bc752c68a0b199dccad084d13f7ec645c743755d565d3a8afaf2a54770c53c323bababa8c516317ffca4830d0fc4fcc60b7ed58f3bb55d11480c59e6c5cde09
329	1	210	\\x606cf5cc1a1ff84a666fa0942ddf16fc2f1a9a0d17d9e0c51ab5d5bcfae4095dc3b4674f138c8e807f8583a312ef9ead2bd0ad1b0140255dbb73a1e1adfc2c0c
358	1	316	\\x8f26ae7357452628e4ba1a2dc8c044a85c557c92b2079eb520fea416287fd46a68ac5df868bd941d2e602f0db1ad797f3e8e5a5c446adc5d72d2b3cdd5338b0d
371	1	94	\\x60dcdf22b0db62f428779620a3bd01ff1b593d109aca8141a7c27b31b49e5ad110be1eea09c566417173fc97bac453d7cbd0119197c63112fe009360119a2708
408	1	260	\\x3711cf75d8010718fa88add0a91749892a6693489668e672af1de832d4f0c881f7769dc719b4cf9decdf3f76bbd4fab721631b3e9ed354aa1f403013a118800d
152	1	1	\\xe4f4c10e06793d03de421fd3cae99e57ac501636f884fd74ecd05424761479554efd813c6ab6daa42701d04293211b44c711a83c3d305cdb7ac5067839f27304
173	1	11	\\x7e1872dba1dfd4b31628f4175fbb55f7f37023247571fc4e1e04a9d825959aa4d1bc388069d3f061914f91ed43bf5e1c70e910a37fcf6227728eb8d18c85340c
226	1	77	\\x8874bc152db9a82f3219d9f8ade59ac6916407fd04f1f726cfb353eb843606e9e493b321d22d832cfd816084f8dd9444ab374d93f60447ad4e96b92fceb9da05
270	1	133	\\xefdad67d1fff0f07e8bf4832100f2325253bfa88da5395655b757bb272e7891b48a978c1e8fda5bd636abcf7fb52d7ace00c2048148a05b2af35ee4fb34e7a0d
312	1	419	\\x4f82ba469759f63751f8fbe9862765b44dbeed71ff6f93aa575fa560e8ea86c8019efc5c675d37243297e21466af51b0c09d9224bb20d60bdebcc4ff78fcf103
337	1	45	\\xf4168f9cbf85d87c3b985355b819dccbaad4427c2f6c1a817d29bf6bad20fabe944b74987f578c69769da96f8cf7a2711a6c4419662e50040e568aaba04df605
383	1	374	\\xa240fb31025027f2a2688fa835186628d9a7ff608733aafb4bdc7921c74ea6eea61105ebf842bb95a006faf22abfc57e6f5b687c98561e86a91f805ae25d0308
423	1	411	\\x9b0ba5157d397ab2b1329405642eb3e9fe3583945c29459ac5f9d81cef6b8d4eb9351f9fecb6d1cdf3afd6be54251a2759c1f4d648d1dafa9620537679ddb100
153	1	302	\\xf746f5f7286874dd8c195cc332a3b80639f57c7489389e807bb257d16627d9bff63f1fa9b039da213d80fd057ee990ce324bedaae954d27d1edf7a0a17295805
185	1	320	\\x183347c68a1b51eeda1172cce47551d384d47fb0f6808762dd4f6a3b43848eb34ceec8421deb1cde9c81c4135d7ef43ad7ba6785449833d24289d150757b750f
243	1	39	\\xe676c2f36d22a42bd420f87344aba836b3888154ffe8340ac7ac0214228d6e6d7cb0fe0f142f8e4c663860bf7a7c72aacf1b373cf62b44331eabc3756f79290d
272	1	279	\\xff3fc5f0f2455129c70ea631ee4b1895de6c8aca141a08949d747b0b51f2b2f35d5a89d85aabc300e682d998c1c6b3a758afea03d3108ee824ba6ae0a23c6607
314	1	410	\\x1a693d8771b7f8b96125e19c97d9a78fcad4bcc0cd49aca67c6002e17dcb083ff11b389930a385fae7408ad39f85db3147f60c36f902271847dfb9cb7360aa07
346	1	417	\\x476b518730473a685ceb8aad026cacfe1ff4486a46102a43e23ddc759a0458b7529d5bc3f612e65ad73babfa135778df00db0c22bcadb20bb015bc7594094104
414	1	392	\\x5a7b336b11c69d7b05c7d7485aff3304e1da50aeeb9f33ed6cb7830a9be9982022704eb4a37568411fb0d7cb09fbc94bec4f90168dad93976224b8e92c6b6d0c
154	1	76	\\x5026fbd378446beb74493d5239d3e7a9bfee644ebd1041b87f330bcc329c57fb9b8fc151e5975df0bd3dbc7feb53951e5f890a689d8f5517488f6d32654e7604
184	1	327	\\x0fd54cbfb3dd872ac6b8a0e0865acd9f048b877d29777b28bcd99c75c9cf650c65d6d7f02581a0c7ddf07019389b4d7b50b908259ab03457d4a50cbbc6c34e0e
216	1	378	\\x0f137df72902295a49558f34adeb8ef203f94c4e643f2422afa11e15317c3b1d00740628f611191a0bc8fc45292d039580e3e12d590ac666461f925f0e881b05
247	1	245	\\xc25b6636e66132acf2ae4b5351130ba1a77b60e66f8cbed1392e92caf127999c76c18496fa32425aef93c75e041510b402ae8bbdfa504a71d8227aa51903e70d
283	1	97	\\x807d376cda6f7c23a00cb1e8d5206b1147dadb56e11fc1a5d465b17eec9c82c5ff020f3f62403389b353a103a3b1ee925d4fddb31df06bc9bd85b85d08eb8903
318	1	202	\\x149abcd76c8ba506e18981a87343c1980f0da90a48c28d11d20f711f661bf0be30fb8cff25f26b1eac147f84302f89f41a3f49bf31bdab4e91c36410e9ece807
348	1	166	\\x5489c0fa3435792ad83418e5c1ad8e767151a7614e52206dbb43d3d803f93468cccb2aa96779968c96ec9f7c2ecec67023b9b9d9c64dcbb8768cde9dc4990209
370	1	50	\\xcadbea168208cd2e3b767fd3e38967af6a0a0d414679360c0ebfad05acdeda18eff8c2645e54420cad911b6c6bb7a8f810b3e398cfb03c098f64fc4e316e6208
390	1	401	\\xb6ed7a60b76917a3e8f2e7851eb1b7a2b14faca85da1cee86685ba44518fe77d3a99b4709b8cb3ba119637e77c7e030378e7b16990ae62f83af4c2d9c83ce707
406	1	126	\\xda5e8e9e61de12c5fbaaac8bd021e4cecff52d4efa515c20a67823f5db6aa1c0b27b7376492e778c04b693f6ca7cdad15f82f9fee57cdecd8bbd092e49368902
155	1	161	\\x44b547c3d9c71b7498ddc56c83a1165406efd78b217036124f7af98d89e09d22ae48386f16b6792e86814a52dfbfbddbfd04c8c37bb0d2cd0ea9f0489e637b04
176	1	424	\\x9ffa6dca93d489331edb0f8f3da22ebdee63dfb3dd963064eeeb8c0fc1b70d08b20f1702a5c8aec31b43ca784be366c46658b8511951126c4bd2c03228f7cf0a
207	1	336	\\xc0b567d18be31c20c0626a7d9e1179aa98b5b047b81c3ceb549a1e371d3cef4558d75eabd29b8f51be3c2dd1a14a26f7c81e00aad8346d560d21ed04a87e9804
251	1	81	\\xadf414d8e8b69a385607f87fb514983382c7a159a3168718b6033f0bb7c61c0e40e931577d448a8ad788f6621fe90a2050c2dc45461631663f927b651d93290e
271	1	198	\\xdd445ecc7b3b2912c52cc8feb39f2624aeebc38ddaa679301ff0e59c6d56eab0c8245900d15a9462c9462d5b9631b07e3234d5731f606ad598c7e04b83c8d00a
285	1	257	\\xaf036da527f4f97a1f7bce8d992f5d99ab8a31332879aee29f9f81a8703db521c3c5be2f8ae660c7ad50914937f9e812e6d3cb32d4e605e353c04d567d293507
306	1	379	\\xf8b36fcc766b2e5cfcce31802dcb8c4c69c3c8d7f89dad8eeea85e5ae3948704abbdbd06eac54200e2802707aaf2d9230ab714593c77069bbd916b9cb7f68c01
340	1	163	\\x32af8910fafba8f524401999f98a157ddf9d7cf691f339bae0b4579a46ceec10f332f095448028a3b7f3ff7d5d686d09828893375b19d9cc0259be20820f5b02
384	1	288	\\x6060f0a68cd6de2f2ab66194fb95e77d2d608113829d73f8c5b53e90ccac9a6e4684c83239fc657e13ad4f43346aa71bb217457b2ae008e9a694cba3a956a10d
394	1	228	\\xdd60f88293923f7dbc3124ed176b4421f14bc88c7b85bfb8fc4152994ae5b47cac275f07b4b6e38f974059487a651bdd2f3c25973d9532bdf8ea8472378fdf09
156	1	207	\\x181634207defea97a6ab87b6c247dfad6c1a64195f80424a459c93d304f8847ffb9e433625bbc3de96aa20482a1bdf1727c3837d024a514bcb0d6b9132446103
180	1	294	\\xb4ce81e26cd95200a360150e4c01c3689f6f9478ef99414f35d6b4cb3d2a2dd3ee795dde7818917cfae45f703fb00617af1fd89ec2f7e2ce827751b550342309
211	1	313	\\x7ed1b0183f2e560e59d4cca9c3c21081b41c14b5f01ad5ff9eb94fc6bdbd0bade41b0d5e95567ad5762296de125f38a228259149051df39450822abd7f826c01
233	1	19	\\xe50ed19dee1637e2e7c07f57058653f077c3468816fcf1ac976b8bc1494981c855eeb8e2e6cb037f8da7c6dd4a4b61de21ff9cfb70675391a437d27196de4305
280	1	246	\\xe6ed398ed05a2cc150a221f055150e5bd73642f6d7000b08a4eda36b1e160761b14830466c8e52b7ce945be620d87ee5ca9be31bd86b0358fe400727872c6a03
299	1	197	\\x4f89dbe36a4bd13eb4970eb5fc3c6f3b533182be6a0399d18b2c1179987ff55639522438519098334b6dffe1acf93bf55a037a82c28f630834a337cf0c8a340b
323	1	223	\\x2427a09313f9700618aceb3dd7b759fafa43a2e6413898f1b20498c86d3f0d34cdc87f604ec7f922802589c9895e59d9af1274890a43ecda57f1968344c4a409
375	1	381	\\x5780cdd2b5bf4c11aa0fd8c47125b7385ee1f8fd30cd0803063142c7e008fff54b5d563b80c00354803b9550a15ee644e1c2fa05eda0c4409e09c5424e0a8509
404	1	55	\\xb789813348dae300bded7049a3a37bd94f0bd5b3f17bba84c94d4b22cd8dd08952e3947696a5e79896d85d84938ff8eea9fc58ce9b32b893e08b5f4f6ebf8706
420	1	353	\\x00f301f18ea4113397c183a890f28c9c4f72c07f6b65fe83205ad930b30ef7aa5886bd42b37af45c526828a9fc5909e7f51cde4c366dac4d7f2557e5c0d88f0a
157	1	418	\\x18477a17551f7c99a34e8b976ea5c8ee2a1f397391ab4cc2dc6f29ae97995adf78212bfc8bd9fcec1befefb07aee4fe121bf06fa3a6a16af875c7a8e3c9dee01
197	1	118	\\xbb046ea5a54300179cc1331713c3b56874b34b109c8acc0109cc5a396c2a77960f40f9bf1ba7473f5da65dcf4a02241e8d17e04de0da872c2a234ba756353209
229	1	113	\\x418441098bbb25538305adb19a9d2e6f249d11f8480c7052ad22bd3738f8aa2d99c826f47c4564b4d321ff26c8f67b2e606b99eb7d8bcf20f65ed7afdf2a6606
260	1	408	\\x37f89de2d1759b62644aa6a2e0e32b8f59db5a049e815bfe48ef284360c944c7679d5d995bf3ebee62c71a05c2db23f2840c12195d71fba10a06c4fc6be84c07
287	1	17	\\xcd2cc6ff21342ccd36a98c46e140f0cbaabd7a21082e9d8e5b9c3af20db7a065ec794a9acb55c2174b8ab7b17195745aeb9bdd5a50c1aaa9713530ef53befe0a
316	1	247	\\x006e3b49b7dde71efef6a6d289f361afc9cd2aa4dd107065df508b0d448e7b48954a12da1651c7da0c6db29b17beeeb7d5a718a27b0a5fb16eca032e7738f40c
347	1	24	\\x3e3452ae6e7e1dc0f2b5f27bdf485e400c9455fb0af67c217b45a3bbbb259243f9fc36f83577d8502dc381ddd98bc582c7eea549efacc337fc5edc287bee5f0b
387	1	215	\\x1c50fede36a7f9e294ebd8e805c428557c3988007b37b0a0380d402d9ab9dbc4f74121fbe0b820ec6b6d670eb9cf700b94015ed4168ddb11b61c7affa1bb7207
402	1	195	\\x7ea240b439ba8e1fdee5159ac1f80854ad5c93e5d2657a215f7334eda0c3addcc7e272441ce2c5345e3cffd4244b5fac80fa4bfe163a6924c2e7dfae42be0a00
417	1	3	\\xc0119508f9afddb378607f0c840151685ac9594b0760e10e66ced6f78c9b57e699771e566e83df519f10cfcfa0182b00b95a740628596c1d821a97cb40a21a01
158	1	282	\\xba4a81bed06f0996ff054e237bbf44f44b108cbc189e24b8e7e0624b77401b457d766861e3828ed6ad3ff5861a10f919dc722cd392b17953fa5fd96a98365508
201	1	251	\\x11d5582ef6e5ca16dd6ba424d7582017dbc75bc0d63c0c3708a347988cd98d6933e31a2ae5b65eb7cb9daa0d48b8c53bc29a7cf7504fcdb0973df70c4c4b0204
230	1	104	\\x8e8d78631030e74ea574b7df3d9e532f4e6292e543f4ff82f4888edd6fcd8c172544148aa7b0fc1b7464f961d758b70a6de742eaba469696727de12f15864602
266	1	41	\\xd3360a0957a864d86ee33dd85e9146255d6d9f7d602e33dc6012a69ac60352315ad3314da620c4502c29f08d38a1e6a5513e0bc6818b12b45aedf999802d0a08
276	1	49	\\x6ed205d1505ac7e7f4ab047918a5ec712cd7ad9633035d5bc70c0e6a859b3daf60778e941215e635631f2e458ba9f0275a082cc098376293d1edaae24398ee09
303	1	123	\\x844066d0ced3fbb0a4930c03bf3984e03b71b6f6dae700c1d3533015a9f23276dfd372b7b3b870e2bec0c7e7f1cebe228e0eab43396e7bd3c5bbb54ea8504509
321	1	333	\\xd256a5ce05f890048224bca7fc997c58f1020b3e48dab702fae73358fba6a4c854eea16da63af7689a76c8473a3c2f02685e0549e012d8c4b040a6e361cf8e03
354	1	293	\\xd63f94eab11d4f38d21d5efc2877c313597b25d5a4d145e6c865a2e853d293d14093ee460dff962f790101944870236e71b68847415c8dc264e8e9160a0f3605
385	1	253	\\x906c9fc8af37d28135100951e9c8e3c7c202a27b8bb3bf5b3a892202cb8930c07f777f8e10f1ece99ee42b19d0105391071f39607e6f3fd9f9d665eda1ca5404
410	1	27	\\x2e4d0a3860065de1666d85e0f7bbcd90ef93f213e597833716f5106cea907dd4e4e49bcb4b55ed2d8da395bb031d6dfb1c0f32995bc59bb55fc9bfed65053904
159	1	300	\\x8d0e27b91906f3a124fac2ad7c26032c0d0a2559a13902d68e91e042030f04648c127eb149e7321651e5dabbe3e1e82bc5e404757c2f866cf2a8ea62665f2604
183	1	6	\\xf83656b50979bc0148f4287acdba0d6459648349259691c535e993d3f395456a425644ff37237cbda30ab6ce4e782587d4f89d3eef7ef2f549948511e5827408
220	1	53	\\x256e61ce15fa6c2d40f6ed3edb650882e79222c888c57ccf32d8eafd9fcecd730a1560b1e36fb1e94c142313e3d53e23550182da257af584e1ee11514a7e1104
257	1	315	\\xf390c7544ed8bbe6c297da469fd02ef2055a4d2dfb31f452dcac574fd86594bc2a6a1a8862f7e1dd2ee71ebe732ce5749c9955e217f92b9b2b6ede6fe51e5402
282	1	287	\\x9b73a0250795cbf2a4c07a60e50dc2c4377512c88bebf15112a14383f62b9c30b95642e527f59d6f7f8983ff82425617c0c033c1fc5727b2e87cb535a8488800
310	1	356	\\xaf1254400e97f2d34f29bfdfb4d095d751a3538d506e0d268a069e8173854a62e2c64f6e3c7955d2f43f162c665c318e4e5cf47fa94cbc751b74b70b9b34e108
327	1	389	\\xc0f6f4d8829911c7544591cac1e4b99798c273b5a4d60031396e3cb6ac4fa58802a089b3866a4ae5ba9b10995e581f0f7ff96820f3eaff86cf6f7ac6a3938e08
424	1	203	\\x98431e3fbe75b88e3f08f46cc2bb47fa945fe0b3fb0efce7f27f8bdd3759d91c5ccf3d9532e920672b0af188225e69872803112cf981dec0d4848e4e9e10ee01
160	1	271	\\x6f6707ddc8051a17c00fc46c49ec7ceb667a15caa649c887055c550cc93d36b9973083887b0afbc429f47d3609bce402e90a08058b3ec5ac91dd617c43f3bf05
191	1	65	\\xdabe987dbcb09ac5b299c26c73cbc58d4c23ecb3809d8d2d7d0fde60884b1e0244b9d8aac52fd546b13e58f887d71da8ef0d747241e716fa6a1c9452d49bef03
219	1	278	\\x246469fac24a96bd5f95dcab2409dcaa75f628b4e790042848c830f92d6ceb360c086e6fbed00e1afd6c9f6a7c3e928b6ec386ac0362842112a8edc09b58400b
259	1	168	\\xe9b81e88e58a236f20df4355343a5f51f55a22a17073ef9c5fad3444f9b82cde6c59fcbec944eedea8751d609989762bf2fa8e5bcb66ca0defb43f124a1cb605
296	1	262	\\x97a4067cff172c2ce7ae84f2ebbb60d668ae7f20f59f89bd4fe416df54ca2861dde4b5c1b0daab78fe5e59a8c368aafd19fa32d69a324979699db6797251b80f
349	1	250	\\xd5bc5d51b25259c241dda0ab2313b63536de98eb64fcb00102b20a57a5541ec1986161ccc43ba37fd4fe4fbf153ef4b3aa7dbd4c5c1bf945a1bad52a4d050707
367	1	18	\\xccfc2792319e2077ff0be3c296b8da95df30c2379ddf4585af6b9d87741fb68e9dc75fdeefc8d0c04fbf295c3568887e262c0feb56f5223c24eda3ede4b03207
380	1	32	\\xa2ef91296fad8a4b4d558b41757d95ed0adfaeb5ad0c1dac9a4b7ef7b4d12a46fb539060473537e43f0807fe155abfc04e73ba0e9300d07cb18b520f9c7d1109
392	1	56	\\x0220782dc2ee591a8dcf8e3d2ebfcb3441ad271229e44bfe102b5221681b15c3795deede1a32989a776ed1c5d91fad8a3baaf9e14ffe45ce6b3565b6688f3206
161	1	34	\\xf79cdda2a94c189db06e81140e52d9e94e54a3133b11ff8d5bbd7a43064703bfbd6935f87c83fe9f8d84d6bcbdcc076b95754990a499f8fb1fe78cf410b7e10f
175	1	7	\\x601a8e196a484e13773a471ec19a0d7be76cfc353d6a43bf805b9e9f084c306ecef909fa01fd849a4530123d38f2e95339df0acc288086a5d095108556e41a00
205	1	138	\\x514d8f55a6f5cb60928bc18d40fdf86afd3a7d9282e25143187249ffe0d2b051adf65bac406c17181a72af71854036a7063bda3469509a95f5cf8b0e47e5770f
235	1	354	\\x5bfd035d3993c5da43563f5a541949c05f81b417f582e6baf636321eb84f70cb1eab752aff52bf787833205b4f1fb814949a9e62abe3dacdfc4846e753feeb0b
263	1	172	\\x3e8b229730c4f91d19ad326a22f70c77f9d16442287f24b0705701b22a8c05cce4bb0f52bb35e94ec0eaff36e0607be06fe789b2e22242f00481cc49a2a0e901
289	1	72	\\x06d2a18eced62570c9f89aa1eff57b7c2a4019df6811ca691acff86b3322c278b409d8cc493ae24e2d4a65881a418723582bdd159aa1aa6c5ce95441d7d4db0d
352	1	46	\\x7bab1583db8f143540895888a44a2ab3ffb7e91ec73c76063ed899ea848592e300a86e05d2f7ee7a33924911268360464b182ff7d756d1f01682f6fe295d640e
381	1	351	\\xc5ca7b9c99e29425f63d741da1f9884cffb8f84252d2757226234038c46307e8596f93c5ec99ce73d37b43b706f60febb13c9148d081cd5b1ba3c45737ed130f
393	1	88	\\xe2cd881c0e4bd70f5b94d47b0f0209e78177fd09f334303a342a0bdab467f12328476e73055c71c6e38b4843919dc5e28a1ba8e9829ff0fc8e899b08f7908404
421	1	364	\\xd4cf86c4664ecfd0486a0ec020afb13fdd30b5299c29e98cad96d7412721969047139d11218904e335b53d44fc596a03fdcc62d8b23b2d28a79d9d1770eee402
162	1	178	\\xd5785bdcd841c918607d60d573010d7f59605f551f9fb199e915a6d109333bf9ef231c4610ac22c0e25f8aa87a59628cc2485fcb7506e4cbac7452b107b1520e
190	1	206	\\xcfe3278fd8876ad28ae57678fe8928067b8a7e5bad629958b1089087dd569a242174e5d647b38946f25a0f878edb55e0f732f9a29d2b868252da20f540fe2d03
223	1	2	\\xfb56f6e0e1e029cc11a2677ea7adc1c0e7e05b094130866a5e70e5758f5635d13b887b65879a1ee658b606172897feb4b173213dc042e1f184cbebc5b5d5ba06
250	1	107	\\x892c343d66259c9080ce8e31120a8a99a1c0348d290c82082af9e9fe0252098e3a29a9a215af6001cf89d3f8e26ad4a22aefdfeb474984851223122222c9ba04
295	1	348	\\xa35367655da9ba4598b5eabd4f5de2e86c44f1f5d86e22248dc9ab66d1c419215840a6a0514009900b781d853618d67cad03ee31baa806c9715ad597f4a5ea0c
325	1	130	\\xdc084ef1dadff42e1d5595f3f070f2904951fd3c32eb6dfb5bdfaf243867b802a3d43a083bb566baa2e9a6985175ae240648c4a7af629aa17208a51c81d26903
345	1	269	\\x1c4f36841a75450fc2efe58339506eb970b4d46da90f50231aa703a6442de93788dc17d94cab7b7751ede8a22889aabe9bee3b4d3bd0f54ca5708d53065ed104
363	1	422	\\xed34a99ee21d97310724e641a49b4a5f445f807150595fb2d9bdbcc0f8a37647f4d3f900349ac26f7dba8f13016b66b13c8c078d17fd14abc1c16917774b6201
374	1	52	\\x6635de705bb349f858ae36decac289b8a5f611245116e8af87910f752a2ea2e60559d7007e68c5ebd2e1acd5290f3ebf35df2a3d1da9c6720ee38385b4a25c04
418	1	103	\\x1e5b181827a7dd0b8a99f8fe7737e7f06a07e205128c3a7e90364fd8b8e6c00bbab009cf47e5d56e351d5021bc8290a583bfada0a33314eaa899761c37036202
163	1	340	\\x3000ef1fd0ea355da0e312bfb8c945642abc9864abe8312250e3ce1ff73b951d427da633670ddc67abed2ff1ddf75253700ce51a8f6eb06f12df3de87af42007
170	1	405	\\x07ec31e709b5fc1914054872b503a9be5bb519a941fba75c6218c5e67ff475893897454e48fca177360240d281a2896f7c762c983695bb4ac9686bef66dbb500
200	1	330	\\x6fe67bb629bbd3a0d83a5e2d853c83f74d859698eb6a4e0f4def370b2f6c12f9eda57906c05c93c7094912f2fdb48cf61db02d0d64cb5815d6c9c98d1291d803
236	1	362	\\x4c7262a9e473673194d3c1f22ca400c58ffceed8aebd2c326c51b280b218cff3a1a49cd72d9073326017eb14fd0aed7adbe627d4cd6ae0b15d8c04317141e909
265	1	175	\\x870fd3f7fd13f6497751a1e273c7a398059594c5c74ef5ee57df1da54fd0a46c77897f985a6679e079a3559d459046e6dc7fa778c3086a8c7a249cfdd4f09b0f
294	1	156	\\xe69d6c59e2defe62bac12c68c4d05e587f30cb9675255df6bb419bdb8c5b9f2bfdb6630c8b80c888bfb11736b1e56871f2908d809d9d74a4d0c4a0b478d8cf03
343	1	399	\\xc13bd3d83f6075544dfc04b260f36602cd2364227f7bdfc06f00f16194aaa1c3c94e59b519a64809d28d579a1f34c9298b6c3f90d1d19c7b78cb6e7673010909
356	1	375	\\x4f31810f48efb241bbb417b39a4c596c8de190eaebd1f65e98c9d6f094d9744b31006a846c53545c96a00fe5bdbe037e346cc8801042c44242d18c922a49e300
382	1	295	\\x4fd7831609c0c42ee42ad7913a416838275b589518cb19be30956bbb5ed4e940bcc77af2532672f26a82e67fa5a2de93ee17944d78a7a0c54b7a01ee50886001
405	1	355	\\x27cff9d1640f69cb92ff4d9b893e4dd1e41ae0cf3271b844843c742014e4ec58153311c203f3760d8fd9421093b341a957853b30cd3bd2fdf9734695ea07d400
164	1	272	\\x35d6a5eb7aeb8b00bf023513f51f79eb384029e9777df2f14e847bdffff643f84368f77d9339bf7664856c7492537e8ad602d6a2ac2d8a3230cc0e29d8afb50f
192	1	89	\\xae2597144ddd57907704f81ccd9d6a8b55d040e4b0ac9ad2361e10581a8611376feac3b055d6eb340681f33fe9da27f578b42e97db63424b22126a83fa001408
227	1	127	\\x2a3ce10464c853f023758294151bb89601bbd52035d08445e73255a2b79887d21743657411be876cafefc590999e65167918edd668a3b1bf5803348b655e0604
252	1	394	\\x4e3b18999787e523cab39b74b922b9d2622387357785be76ca41dc2ce7e65bf6ac1439b4f0db8f72b81b8fad80440563eda41815e3e654704a840ce54204b506
273	1	305	\\xac105e68be58180f343b5ba485c58eb98c10728d5349275b5b5a2c713fbf34bed4d2219e08679a65a8d11cc1736a70449f788acbfbf571cc2ff5ff9ba3186107
311	1	265	\\x9ddfed67c4a122f4c36a85e554925824aa6a0ec3268e44eb159d4e3a8ce4dead2571684084bce6fb2df69cfc064bf3a22ae5c1bc16b2f06b326e97764c2f6f0a
357	1	266	\\x8aa0f71add227a8323056b03539ad73dc6cde436b3c5d0684134253eeacad555edee82b99939bdad5e8df894ee18f76d5ee2a3e825c2b2228e31542cba823a06
377	1	319	\\x8bdf4636eac3b8ecd25e8ccdc02854c8e7cb8938c86905f4011065f829a7b51c0b2c6e8598f88e75dee8102de30348ee091dc969a4f8bafcbce4e90776c6fb0e
398	1	391	\\x8bfc915668cf526b1e419b23b86f8fc08dfbf70fea75126a09ef9dd623981d68cfb42a37d6f14980d03d86d72ac37058794b41b8e582dae32fe8831792bf2c0d
419	1	66	\\xb4a98dabb090b4f49764200020112ec625a63247df3ee485b0b04c82e8c787e673cfbcd01bef2077378e37cb2a12377d10ac04d43a5783577bddc610ab35d008
165	1	73	\\x0a017830f3ef5225c5da19f39af6ea5fc88758218dc76294c86661896ee2d78377b7f7ac8a7846eedcdbfa64294db267864f7760dd87b3ddbc25ab1468f89f05
198	1	332	\\xf2706d215bba2d0119d01a697c45afaf142db4ce24d05d657534b1c4d9b5bd110119f5b0f3c0eb4a2b7968b50106a79cbb6ccfe936735a0f5626ebcb35136206
228	1	343	\\x83d58deb6650a3b57d9d85993511327ced7428492b167abd8af351d01f1943f862834057678c46b76156a3b9fedd9f16466aa75df604f4590880bb16b9938706
254	1	393	\\x3bbc535bd84a70ec1a57de8b35f8c32748935aeec8a0385398acdb564377b29383bfb9df2a684d6b6e40d0b986d777c6703d9bad080ab87d4ec6a6e39b385909
277	1	16	\\xa287676c6958a3eaadfe8240e8db9d7cadbf417c5ff871679840d7fe45517e1751b18ad453759f16dc3ed7f4c849384864165abfd465c8429c45f8b177804e0f
333	1	264	\\xd71075dd91168e0e7db53b31c6cfd4476b1dfc7187365002432193a579f115263a26cbcbe9cc9d2b0c3e4b1e3c1f3de5303a119660e6b2da48f0670e993dbb0a
399	1	151	\\x0141a90240fda33ee9616c72772b95d1a24e355e8e96d27ee9c5c08bce79ea31636255a4afb0a7771c221c01affd4662ff0c1d8d7112a0f74b67e255bb962900
166	1	217	\\x518a961ec80f8e2826abdf96429cf9d6ca4b1bff26b4b4d74879c9a8ab9717b770ba86a8d4153b44ae2404ff54e30b56247ef5d3017d3ca31823d27fdf8a8405
187	1	363	\\x647a113537a2555374c101e47a81b1d5d5a71e54684255387cdc849d7e858f72d900d882c4792ad005c93bc45d16b3a9b06954f890c161b16d47a332b4ae490b
224	1	36	\\x5e70eb9bba3ef0716e5b1fb42319840ada842e0da9c80cf2a87c36f806f586ad7e719bda6dd59dcb8f553b01c87f67f9a7617b7b7ab1f1d7267ff2359224df02
248	1	164	\\x2f7561294d5ca50f05c6c05fe553400c28214c9c2912c5fff53219f0d0c31f1fc7a3f5c9c7606611cfecfc7260588b0d04fa8f470cad8c1c01ad4c98cae4c40e
279	1	373	\\xe84dc8965409e1238fd59f398dc4ad62cb1111e2a40eeb5f4d5e2ebf9b445f66c1fa68df91e79117f7246efaff56eec34ec238ea6e91b5479c33c28d64eeec07
293	1	241	\\xf80ad70e25b86390f75a63b6be12d6fbf2374e5449ce929e278046cbb5655f78abac196045afa35d8b15b49f14a05b3f099cb46f544c1d32c41c8083411cd90e
326	1	199	\\xaf025e9732f4cc7ba37a6f4a99d8ab5aff1b5bac25aa797c5bf085eb6220b32cd9f778b1e714ce29cba98c9f9f6e125db9b5d343ecfc4fc2090608088ceac50b
350	1	12	\\xfc2c15428553000d7de644d59626984c70e18111a6ffec2dfc116fefa993364f757b168296ded0e6a49fe844421727a6afd187e969cfa8633dbf6b6707e94702
364	1	116	\\x5899bf03f258c197edb3cb3b24d5a322726fafc2b329c3afed9dc7a9a2d3e0a0584358f41fcd16623cde1fa7a4c4d879efa25ca30d35264bcce2fc38f583f305
379	1	122	\\x3bbda454f8bb6d0cbff7fc9403126959f4c1d102827dc132633d0b3ef24be7d87c9a323851dae276488181f913763f11b9322ede7cf6c2551e28160692116d03
167	1	421	\\xc6fc6bd8887575d0003c542f197acc475c3db75fa1502633a1262b6c91928e86ee674161bb0691a7297b9dfcd326c18bd32a8225ec1c507bbb93c726593b5603
171	1	43	\\xd683168dbbb7a0a2b599c04d202d0337607f0fa0fbea535d30a19cd123e7bd4a4df71bd6533561732865775548d88f0058dfe7c6b9392d3cdcbad1e2e369d007
203	1	416	\\x1c4b2beebb3f03eb29830fa5e96b2bff3bb9850e627985078f99823e5c84d3fd163f7089d6bc7c2ae320f7be0ce411f44a7a5a3fd5f09eb46c66f60fcc20b603
253	1	290	\\xae03b8d2d458acb825f082094c74e7b925efcb7005301f573453fb953b8ee88071f56a771fd58e0c5561d2fc5b0e848084ac13cfe182d3e7de27655841946200
269	1	400	\\xb1d77b8dfb52f0d2f1833f73272e9dfcdf7216df50290f84b91613bf37da370e60c2d34f62528122f708c929cd8921b3a59d1d4b3e81a77faef22812418a9605
275	1	367	\\xebea8051b73debeec93de3210c480823368144d64b52b85d18a47949722fc27e51bc8bcc304b509f333741ba9aa10569195fadbeb6485a7676aa5276da0d3d08
290	1	406	\\x8d6518d520edf7f301ed127c5e082f1082e12945eaa732251fda05112f4cfd0e37a8c7853d9e1a7c06fc4cfa8e027d194179839fdfd9842276d05f17448cfe08
313	1	171	\\x2d6da22732b3c6f15ae2423d410e054c13ec7e258edb5fc8406f9d9b4fcd02d738f3b9a0c6cf27e8072076ac741b622b399ab2367c4d71117811d482c011d80b
335	1	196	\\xaead2242b5e4f91f5243c06f8fe8025daec57c7ccce8cdedbb8ef02e9289f32ad39b38ca4a0ecd5a451a8e7c6d301683c0150317469f5008a32cd5eed0407f0a
396	1	224	\\x6b7ef289295cbc7a5229438e871bff4e80f8f092105580268f23f2a5e97eed615be924a57f5c2947331b49af616b85064825bf9724f1f00c654e906574c17a05
416	1	423	\\x219c5f43609c6d026ccbb16c0d495bdcc9f9feb953f351d8cf42371d5ecaf2998cf2e94e18fb9ba30c400b7e9cb6af5d69bad24b85ea35c5b3c567c51f098903
168	1	259	\\xbf615c83f9d7c3290e6b0c51bd73f536524bd2fd188ac889b9df35a82f1cad98b7386b0c7c6400ab47fbae9fcff7056563960321661eb0a362f1d85a229a4801
172	1	121	\\x430b1227d1c8c80e493dae7aa75ed890cb35555a372f2ca0a7911c654986a1aa411820ac44162fbefdf3eda6c8c680613361b0b1562451b00f87058642ca790f
208	1	60	\\x8f6f4b44839df0aa58a0097beee9398788c123700c718009a7d1f1374c1a378c98f4efea06b2545d1e25df9a2856606a04c6ce390e1791b566f7f3506ad22107
238	1	384	\\xaeed266b0ab02d0423eff9f241b2b0eb4a62b028d465d81e4defe4f34344fd1233db8ac46621731a5e1e4a69e7baa69b0f3541ca569fd4c7cc915afb77400001
262	1	28	\\xbf3d375f4b8f89df92c8dac57ff2b5aea7661a96871dac2827f5bd6393962764f4dff8d47cd776fe7e5c5cee7a2a84c202cc91cdd2e16f5d4c12c112631d070e
300	1	236	\\x3d0e37ffcddf02e3b0950d8c6d057f8d0dd821860ba341100aade2277597c91e52d0e26e5b6a2d5566978202c33c309ceb61aad7d4818f8266c61065163b1402
351	1	306	\\xc38194e1cda5319348edfd761326c9e1dc2f4f691269d084486fd1c509c99d5f4faabba2bfdd7b3d14cb956fdc9499b719849aecc9b23e9e1241941deb6aae07
409	1	115	\\x47f67e1fec49b1e7415495d6896023ab2dc18d2e877dc9ffa12b0508c446884a46bbd70f724c3183eda5abd5c02acf9e0ca7be089ee4eaa7902d10e0d326fa0e
66	1	30	\\x8f81dbd26f85b7cfed602a2845d5e26de03f7e11faa67474e4c64f80c79a8ecac4df519b9086919b3dd74e983637fb1a2bd63a08e627c65618710c1cd9a03c0d
73	1	344	\\xcabd181c00cae5e74a88b0553814d0d0fd2b4e65c35b1c14de2ba352d18a9b6d1934f9ad48f1537edd57cf387327fba96d1bfc72a38f22c8ca34135067c50d0b
79	1	325	\\x3b29f0c7d7b3592c0e4f208c181cf4eac32af737074f9aef72a05341b8030c701521d3dd0f5233f2777e69b69e7516b06d7088fd304d032f3afcdf707cf93703
86	1	209	\\xbc61c2c10492fdb071e3c78879d2faa87b70a6735ad6810f0dc24a12aee199ad44fe47f5cb5bb4a7252e79e1b405668984d6eda69ec3c02cc4f6d6a94d5f1a08
92	1	102	\\xc0e3d2a07f6b137551a3344ac000822f82869f57c876abb6c5fe14898e040a8398306ea4121e411ccf3c6a4ed40edf9766c0ea1cd59505d179bb231e68679204
103	1	397	\\xada41f399c2953b30d69ce3d86739c7051eaea0a3da464242c7c03401d9587087658df8572c5a6dc441f50511235ac65547ef75db30f141fc2c8fe667290a401
111	1	342	\\xd8eb0f8f802bcf09e4e9a5df5bcf05e6288aaa1f80301766b1862e85dce5ed695236caceb287cf7aa2bcb17b6a335ed1f66d68673dd5b1d6a67d497ce3041b01
118	1	349	\\x2c75ef8c1c68be1d74953826566e794bf0a657e55b2bc77e3ca1afb3d13851332ee4ad84503f008bfb07fae9610075c3ee7e1a109808087b9023387b42ff4d05
121	1	420	\\x94550207a5e0d0a878f33cbd2e4072ccac3df25a61411adc331d50c7b373ca08fb9c006ed35df9a85fc2231dca3710963cf227c8bb5b7fe62f1dcd48bfe38201
128	1	119	\\xc63cbdc7316711c2160d101fba95acf134ce58ca88576beb9e24209494268a11ef13271fb89c70487282d239d4bd6b16748c52f40025986e9bf7ab25650cbb00
135	1	310	\\xcf892ee0acd8e1d270c199cc9c93871e8eb9493f974b17b4765f92698b34f96c3348129884eb05298cd3f7d0b8c1f05212a7e3605851be925f68d7ea8b80bf07
141	1	22	\\xff2f135d1ddffe415e64b52eef4b9282811b5380655ed042f8f3691bc90d3360cc6d807235bf1710bbd305a6cc8ecf05a61701d5f8435b434ee4486831e25c05
178	1	92	\\x0a0bb7a77089a93e181db533c6f1e1e13967b33e7748f5c7141ed14da6095c2c08d91d8aa17f0dcb8edfec8a48fdd0b1abf29f5f034adf7b8852e15fcdb3cd05
210	1	243	\\x21cff180cf6edb1861016f74335610c7a0708ca0bb8952d30b57cec0d4e84d2ffd36f97107693c9c16067bc854f6aedbe0464c4c92aaebe4553cab733b100b0d
231	1	404	\\xcfa4b67a4ee2c883ad88438a6e1c607a16a045ba0300a57cfb1e1bc1d61efa59a6de058894b927e80c55d2dfcc2bb727912704769c1fa726b72b964d86049504
291	1	235	\\x166ba50e5b587b3d36a060f7f528ebe0d2b241ceca6a9095d7d127cd54aaf60842b5c28d9f6c8459dd84bc86ddeb83bb7c89795131032a379fccca76c9bdc003
353	1	352	\\x9aadbb3391156dfbf127dafac062f6a937d2989dd9c5e228053bdb3862127307b306f3e0deb577ff11fabe4b5a031ac7a9ccae772ef02f17b283efad5d16bc04
368	1	240	\\xb9219481847861f90168e6f608c44acc84a36dd4dd78ec877cbef007d24ae0ef54a7f5345ee2542da7b8fcadb97f236c3ae083d349eff45b44525c0aff806d04
389	1	275	\\x40c61fed2a84f14a0a29eab97288849b1402d10260eb61d6bdb19991ae2b0c155214e9b9420e9b6191fd64c198bbf37f909a4aa74efb54873e73f535ccf9f30e
413	1	289	\\x5d188c1c3d85d90c2726a13eaf2feff0ea0c491c7aaf6abde44f423f4263f6c878a42c5ade8e251f05bf1bc783b2d8a8854258211b9f7a6b4e98bc83a3082b01
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
\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	1610355212000000	1617612812000000	1620032012000000	\\xdd1496eb43a2f402d47bbab3ac5b77577b8811296e71bf982922f1b2df6cc590	\\x49f150d910c50bc03233735effcc4e5fdb0628d48ca685dcc6e01638ce0595616aa878601ca98b4528be37676a5aa3ef7a717806e344002ad0df72064e256703
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	http://localhost:8081/
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
1	\\x627461afed4ea5a87dc7cc5a1cc8ad1e7852bdd170ac0e20740eff94cde6be57	TESTKUDOS Auditor	http://localhost:8083/	t	1610355219000000
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
1	pbkdf2_sha256$216000$RehWDweAliSS$C4zaDBeCMFC6vBz8Kep/S3C3RLpp81aWwLhcm3xjsGo=	\N	f	Bank				f	t	2021-01-11 09:53:32.917223+01
3	pbkdf2_sha256$216000$P91hXPlYBQ4x$EI4nBwV2pax9bML4WGV7qZBY8Re6Cqy+TNLsx+65i1U=	\N	f	Tor				f	t	2021-01-11 09:53:33.097372+01
4	pbkdf2_sha256$216000$6EdjL6w0l0qX$q9HQnaPxOwbokYQCSrzLr9wb3LuDoxihLF/cklmporI=	\N	f	GNUnet				f	t	2021-01-11 09:53:33.178223+01
5	pbkdf2_sha256$216000$y20nfDm6Hi4L$JMzRYXi5LUYiEnAFgpwhB1d8o5cxCNlAKJD7lQxHXoc=	\N	f	Taler				f	t	2021-01-11 09:53:33.260866+01
6	pbkdf2_sha256$216000$Cm6PstWqkQ9X$nO2/yD6BMlqD7moTcCOjw04vrWWFDzkUd6rVcizmvq0=	\N	f	FSF				f	t	2021-01-11 09:53:33.34353+01
7	pbkdf2_sha256$216000$ztPmSgP5XNzI$RemzcML4xScJDeHzUEsEohMnGZzyOvXJ/+9MEABuUIU=	\N	f	Tutorial				f	t	2021-01-11 09:53:33.427502+01
8	pbkdf2_sha256$216000$Ppm94dor5Puw$/dJXk/WCkPjsBcvu/vEmUjrV2+VC9uYJHnH9SoEzQpM=	\N	f	Survey				f	t	2021-01-11 09:53:33.512281+01
9	pbkdf2_sha256$216000$yIespOzOuKmD$hQdDDScGg3m6gPWMSM6NCxBK7pzVMxGz6CK0Dn0rrOY=	\N	f	42				f	t	2021-01-11 09:53:33.958705+01
10	pbkdf2_sha256$216000$SBKnyDDikRVb$38aTFbVx0qRyG1Iocg3/1u48ScUHjSka7X7uZfVeiXU=	\N	f	43				f	t	2021-01-11 09:53:34.413615+01
2	pbkdf2_sha256$216000$mNfq2cIYcQeY$mpxDKxZO/hthgeJBFnkyGbEtWseBAYLhR4DqzZjVmQU=	\N	f	Exchange				f	t	2021-01-11 09:53:33.013012+01
11	pbkdf2_sha256$216000$DVdZ2esL4Q2e$qFhfa7fGAGJbc0zDn2hJP15LeZogSz99R2liKS0P8K4=	\N	f	testuser-nnbJGiz2				f	t	2021-01-11 09:53:40.570078+01
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
1	\\x86a75fd2c7b46978893788438a97877a8f89fa038c54a17ba1e44d7774462a98d8f11aa14040a1ecfd0265903eef572408da60aaf85a47c7c5c286178821c809	189
2	\\x2313eb59f910debd03100f8b09bcd65025f3898f75cbc900afb151b1a757b9074f09b143c8e1920dd74b7fc0e87b2fafa6e2bc6a4544345979ca08047caa360a	176
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x00641dab8b176cf6a79c4115bd8f287f79f1748c6fdbf3373f6b407f6555ee9e17c1c166d68e7d414eed3c13df6c3e64079a013dc258767991b807b090c2c1fa	\\x00800003b4a0375e07922c974553c6208f1f83161b4b833e7cc7d518010a77115301960403920d3731dc67bfe4c46449f6972723a2044e438073cbfeaad7fac0000a856b902e2d4d64df5c0e4fad7e42283f577bba616e342d06965e5f1af5455c12e0136f12e27634c2b29aa227363f014f02842adb3aa4cba561a35ec32acf8b1eb63f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb133876acfaa139b907eda8829027a197c39e66ca49da2e8f2b1aa71a455fb508fa2b4e116a9684af59e331902480de49868622529fc48098c863f0b5e263d0c	1610959712000000	1611564512000000	1674636512000000	1769244512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	1
\\x02401941a83199c3a962a408e075544f7646441602bf85b2d3e2ee7f5d7433dcc12fe5b6b4a00e14ce97af96234517a99413aaad89f95ea36b1ed94f355307ca	\\x00800003c16ed0f05ede37b0431cfe3ec2f19bcb2e92d564e50e7adb2b68fae183a68d575d9ea394892810aa6b079a7deeaa5a1e5f0fed9fee364cd667f2e8ef35047b0df10946c83c1c2708a624225107cd3061f7e547317daf338b24758b5cee5bf4953aaaadd1d7c828946366529c00ba04e1658b15461d836533ab8bf9c1421b275b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x0729f76b7fb8ecfb320e9e52494bc3099e668083f8107f23fd510bba7f7f257d53faef8c18aba18db4dfc4c18f4618c921f5e62e6d1711ac7b43c4f74c978d0f	1626072212000000	1626677012000000	1689749012000000	1784357012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	2
\\x04c025e16ac01d0edd594f0f0c07c82bd90ded8bcdd4e8cc992f8e3d1fdbf9e7c537a46ae7403c1d732c350c66f0a93d23bfc4fd56762ade508754a51a7005fa	\\x00800003ef15860eb349bb0a91a5cd62c3c1ea3e6d60d1c85c7eacf6f803a696c240a012596184974b0950725c07d821c22f38b5a811a93731a42509249452bc2bd17f7ce33c03e59a4d51c10b2a84867d2e0aefec28fbb5fca5a145d17188b90fb051c6c21ea852221175744873b5d4124a6bf620d97d6fdf44a67008eb2f4d37b10633010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9efa09a12a490748856f32ec016e3a065d97e2e2dc7675f3fb70a1946a68c1acc294ac2da816f30b1f8f36c84ae1c240f79863c6b1f9fd542ab07b873891160b	1641184712000000	1641789512000000	1704861512000000	1799469512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	3
\\x0414b8ff6ec352c713a1e0f1a3977457314b1e4f0ca93c9d57aa652454bb80db7188e08477e32109a1eb45a04a6e4bcca18d2e55ec909e77271ef084a7cae479	\\x00800003ad957ea4c1bcf75d69f399fe4cfe5d393df5faba78d77b5048427b960d5ecc9cd0fb76a0b98dcd8d0ccc81eba13f4d4ba866da0d5f4ba3586e48d23ead083b6d2c4257fc1c649a894c3b5a3418b1a2c59464c31a0e1640a10dc4af2b563b1d73d34b49b344406e0663cdbd7135ffab0d2ce4acc740cc0c6819a3b3d0845f4377010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1dbb468123be02e625dbeaeeae1634234d7344abdeeeb6abd3d961e63268df636f04304d80d4ede701cdec65d1a7e3ed34fb8e8290768c8bd8e7298072557d07	1619422712000000	1620027512000000	1683099512000000	1777707512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	4
\\x06641201af53234314a354589b457037080062377f56eeaa29c56816a07dfb545987003df043014d1dd9a46519208587c5e03737d70f00973b9287561086c643	\\x00800003bb64ef2d0934ee8ba89ed1383d3a189ef0285abcee4f8eee36a904808f9a8c763c7f2757067d16c2465f50ce913b3b7ca575641ec4bee2143979e55640244871c44359e3b50c027000f393c8c5b14331e080d48f75811c394ddc415fed5c83e7c10e3d4be7e612fecef09a687d30bbc033f3bdda0274041707550878362f2cd9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc3546b08931791185ca74788611166b8dd399b0bc7c9d53076ca1964a1416ad4d6249cdd6804ff721ba2f3bdae2a32d43e387b3124e6dbbde46a8fb893a0230a	1612168712000000	1612773512000000	1675845512000000	1770453512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	5
\\x0d60985491e750863c668b3d9d98980eae4636acff8d724507273ae716e922560449b735dcc91de490ff26fb51d3068527c1bb813e8479542985a1e40cd57743	\\x008000039a9b421de9f9f5f9092adaa12f4869ac3bda967b7ab96379b127307b52a931b3d6d9888cd55da41b9d4fd43b6a154c464792fe724384249860085945120222c623f6a426e3c6951e2ea9af999914cfb751e536dd228fe7f0d442e0721a1e5aa56945f685333b3a498c651b7075599f9cc172beeb83626aee7ed4d6a839e85b63010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc446923d8a350ede554f6561344ffec85484e44ade97590521b7a0a09e2a0d0e1a4d9012724ac10fd5423e01549bab808032d6852143044e543199200e2f400b	1623654212000000	1624259012000000	1687331012000000	1781939012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	6
\\x109cfb2bd4c6ccb8c737eab24e553d4a792f3527f49ecd931dab00858c1d19f1dab32e142fe065fe4630ef4163daaeebfc8bd5297e88461a172799d2e72af4be	\\x00800003c82f91742abb87fa813c7d68aef8750e0cdb662a9ea3dace38b4ef55e101fe36b89751a1103ca2ceb65cae5a36f554e2f9aa15f90fedb7d662f5dff8ef66ec878ce2317f4b68bc0a63f0369fe5e1a019674b95624656d4e8de6d3255d57993a57616b5a16c8301ea36bd41667b728649182045bd3240d7fd14d7721d2448d9e3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xda7dc33cc05b929a7825a9f1608af65405ec1b708925b3d48bc17dd340a890597a5819f3eb3fbc2703f5a135bf147d001b526409b3afd829095a522f4341a604	1623654212000000	1624259012000000	1687331012000000	1781939012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	7
\\x12dcbcc4af39d06f811529cd5d5a07d95d7f0f9d78fe6a66e2f6ebd4e1419c671c6c50b3ff592e7104ac1e19cf964a4c2b042bbc8b0e88039810980c6e0d1cb5	\\x00800003ca104bc8744beadbf4cb77eafef1261db77b07803f074f6b1fb4b032f5fa873fffba10f792125b9e0d106f5b57d6753eeac794009a3c09bad18cb1e2eca2e5914370a16bb2bbee01f27f065176d0c3169e4003430b0e45a7cc30302737c06743faf42c501744d6cceb813665175a9be77144c2e88ea24c984c32dbc241c424c9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x702d113f6890806d297f205bf1be41fb33e6bbdbf1270a6cdec07b7518f763ea30515e8cce757f19f357e109dbec3c2a64ac6f07028a80eb86e8c6a7de180008	1625467712000000	1626072512000000	1689144512000000	1783752512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	8
\\x134cd25592be7a1b6ac5c45c2119a0f1ace494d227b0a906c6fe7e7b55c521a57b54bb164f41f574792fdf4086863886a1b4aca8dbc212ed576a42fc1ed67985	\\x00800003e7587bcee8c2160cda0278fd05e99bc209af94903bf530f9e8f863ccb34bfcf413149dd8da35225014057aa1a1629adc3d6653f55b91bed460eed90803d71c07646a5523ee129b3ea04e91ca183c804a09280912c42fb5ab12031ae036b8b87aa45f3106d49c112e5b803482de5b304cea48ff52b0982d113fb68cfb7a3602af010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x76f037d824e8b149a169d1ad1bf61a168f8e730949452233ea10a6b0137e6cb99eb6115d4f4ba990ca80fb39e5c0ce299b6905ab2a6b5c0b38d78f19e3997900	1636348712000000	1636953512000000	1700025512000000	1794633512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	9
\\x1628809e6fb852f7b16df4f9b6a036d489c9716f62f74e0026bdac0a9a949537e9904b73a299d87695bf50f28d24b30a7db4fc4d3f9d8a0978fbedf0131e2e69	\\x00800003b4853ede290c251ae7857e1c2d398cb13d8eee72501af1a01f9929531f2cd2a650d60bcf153e2e34ed1a49294d1834890a28f3fa6c7cde94e66e3d307b91efe4a5485b7daa71fdfeadf6d1248bcc6eb9e590baea2de53f57d8ea1521422568452034be7e3986e98f608e7311f161082bd335fd63acafcf0628b066e8f149a691010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x210d01ff40298a4c99279c6a456b2e9447f210623cf0e3de78a68dd851be4f3c2a4224e8d4b50543a936d4c05c18b4babed79e165cd03e77b550a44a4d38cc00	1628490212000000	1629095012000000	1692167012000000	1786775012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x19ec88f9cf887909e0ceb105544b175ada3fa3baf5bc36ce25668964360db85455e177362f1713e8c613661c81adac6524af5ab6ffb5e42b2cd8a05b285331d1	\\x00800003dac96dd3b78422026ecfcd0fc01418a960be5bd2723dfebe57686570aec6dafa4c6ca837782615584364f5991fe393880fe75b256eeaa6862bcca768e208a9f65e0d3fb0d312b42bbfd2705f727c1d02d4c27c5fecaa8dd143d4697da15ba2e07586f747e8e7bc402ba2d876af274d303338bda7927d548f367cae0998dc5359010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x53fb4665efd61882976bce38203ed1e7382bcb097a85e41f7ad4363a879a56cfe60480b5adba65768b69b2393d5569fab9484668088e5e234f667b42949aa304	1623654212000000	1624259012000000	1687331012000000	1781939012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	11
\\x1f9cd5b33f1f17ff36ad935483248ae38b169dd997f64e5881abf2f7e2f70468c731dafc3dc2aedb262acfa0783b4ace020a20326a6e1ccedebdda8ff550ed48	\\x00800003df07a2b8e0346901b24e48fbed697f04b3654bb6b5a0ce077c72107162bb8d8065acd9e1a6e6738207c370008935fd4d0b4e889ef673de0ff040e6d8b07571376a9bf353aecca4bbbd0b3401dea20487441a5424ccaf0d5c05e656457674755c73375695fdcddfa80fc7bd0f9d90a2bcbd98660ba7a019af6309d477c70d84ed010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3127d85f45153830873694a4bc264cc2f4547d2a81cb69b5050602f8fb03147e12fc5f19a3c6e7bf2cc4396baa8061db252ee689251f112781d0f57290cdac09	1633930712000000	1634535512000000	1697607512000000	1792215512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	12
\\x206ce697f6c4a7a10899675da30ea2ddeda547eb4ce8e43ef744ecf6bb58c25019e954d04a4e16249b7b1fad942fe64ed9e160b969dd86f471230a5985a2b36e	\\x00800003bb4e372a9a78634dc30c19f38b2349ed0a1a3aefec1a27ba2da44736d69f7e9c91ebccb57d7fd8782ff967671d8d9ba582ca45481cd1255e5f8d7b553f12b768b74f9a8f5dfccb24dff1eaa611c3c2179693d63aac71b9d59a25541e8c06b4ba7a80839600aa5eb5f5e0a971f19ac654840514e5a20fb0efa667ef55ac5f1a57010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x391606cd0cc0267702171b2ea5390ebcfda85ecf7659c4e5dcb9f3e9e0fef10d8ac87c9bc015faf5a11f053577146b43d066bd1062d412676a9b49bdd921b800	1621840712000000	1622445512000000	1685517512000000	1780125512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	13
\\x216c712ab1b2cd37b6a07139f60530a05bbf25d9dd174332b87d62b4e2ce645adfbd8a60e6bdcc9bfdbe748a37808d8ae5b3ca03b0f68b12ea9316893b433893	\\x0080000399e0af0e9c263bb423124084402e9a71f2a60f5e1848d886a29fe53a56f8e912ca9b9b0f1b62978fd9edaa6d5828884e0266bfc9e7d83ee9c522c41f2997e0887e3ca297997dfcc141c1805d09dff50a8a4aa15107bde53325aaae27593b5e5ae336971e81d1876659e26081cb9823a880b4b6a4932231811cd2d3617c521797010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x08a32ac00d9bf6334ee64e8cbeeec149fb762732bde87e1451fc3db98bab7d8c5288db850f30a78303506934345cc22ca1aa5b59bf002d395e4a745d0cd4aa09	1618818212000000	1619423012000000	1682495012000000	1777103012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	14
\\x21a4192611a0084125b72481c3f8a6cfde6b14161da53e1bc3ab6f9dba972c16c38c49bada584162de4e84b2d08338e0e33f6eb95049783915b9093620812ae8	\\x00800003dc50057a8ef3c385b392bbc9f41c140f044fba859ccbb432641897bad78a6bb3504a512d164eba1ad4800bbbe90170e1fb025144e46cab5f843b826434b48244196db7fe934cd74ebfff3f891f549a7beb28774bb1a9dfc3f9f0f611ca95bb710f93974ba7a281c342498c9839de89984ddf9b0b3acfe5a71dacf2e0a6651bf3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4fbdd0b11f496065c9d90e82db76b8a2a782a11d22e3f62567444f9972e0a3ab70db1b44e9411b1357c349022928069d715f0905fe7fb48dbdc569062d39d606	1617004712000000	1617609512000000	1680681512000000	1775289512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x21cc99024bae96c6b827c01e06182cab91b948ba9e3bfa1e8ff20a8a2fc0607ecb2905a8fce2d7356f69dfe2ec247e96be4149cbdb0a762b09326f8084679c5a	\\x008000039a90590908b2472d07dc1badfb139e6e1854d8391e80251d9e06ca68260ea23601c93f722ae6c87882cdfd0dfc19e194b5a9463be84432c4ff47a2b347ae80002684a268be706576af74c5d1463fe26f727331a19793bb18c92108ab13a32df10048a281cfa5d09a6c8fc9abcc77b951078af31e8736e89d3eadd533bdb17559010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc9e2d2bcf2979c176213ae2b1a5babbd37ac134cc5458abec20025d5fbbf265799e9051b2d533e192b2e9b682fc74e24f85942b17cd75518e156457b44acd905	1626676712000000	1627281512000000	1690353512000000	1784961512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	16
\\x23c04c4d47fc3a16939eef57dc4a652f881149c4966016233385686c17a163c924cc776c8e34e019959bc78d2b1bb4d97b8ed9817ee98102f1c8555761e386e8	\\x00800003a53d0b388a6e73b2f7dc1e92dc8a41a7b2ce44a4f2b6e5aa6e592bc220270eb848ceaa3f39b0e2b4ccf812fa133aa1944d2c3e1a8bd64f6369ad2f4f3040285274da90cdde33927f06ff85f85efd5e04fba51a01fceb04866be44dac62fbe94495e7e12d0309d95b456a24caf8641cc0182a5f08371f618e2d5ed5a0ff35c4e3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x52da35b59fe0fdb30d5f549b014332b253dd6deadce99c85a50744ee53408c93c979f3600a09f35526a526eb433ea5857252ed733606133678711f5b1d337b06	1627281212000000	1627886012000000	1690958012000000	1785566012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	17
\\x27ec3d8e1b48f271603f2eab835a338903364e6df8bd5b7be1b7f6019908dcb34eae3f25d39745c95f9998e7559512ad2e2fb045311c7029b57c010387724a2b	\\x00800003b37259dae3e77de2f42715d8e0e2d0a88ed249a3555590a19a1f285bcc340681714bda517fc59a640771a4ae0ea21f6aa7ec4cd4dd19db63c7b83a39c7cb5df2d7a2dbb76744d4a8accb0f12fa255045d74c4aa4717a4979c25071c67510ec845a41349b17c2338e7782a960ea9ebb1e5f70e1bf2e2fbd2722d2c39ed3c4cb31010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd096ec5149a7de557aee887850f7b25c512f322c9242dca3f52f5dfc200ce5c85e873645d0f6fb94b2fb46af5c25ac610932fc0d9281d32c0748b17a44855e0c	1635744212000000	1636349012000000	1699421012000000	1794029012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	18
\\x28b08369a80deb25b21146eaf1b646016baf4427806ac2c2b1dc11e354cde36878cfc327633a5524a4d874485744233922cf42bf96827f4e3f30adcfc6388ec7	\\x00800003c82ab4f4a982a9329d8ec93baffca65f9d884f359d7bd18f91cbb702df0f97c6de55b5060d87af335c8c202ffb58701b27b37386f66caa459c353e5f335113e2ac73d378320b4edbc29e36b0435073356f48f7daa14a65988c9180e954fd5c370c557fa292bf4bbe6ce3b6c96c12cd144cd9b00d2c1027b66afed7034c4979c5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xee82209e3d862fbe30aa441ef1d49ad6fb348db4d4d73d8f294d967a89f92f642f242f09139a2d36dad88b76d005f170f00742d3e0513b11a9e3796f13f0070a	1635139712000000	1635744512000000	1698816512000000	1793424512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	19
\\x2e74cc736a1d421828366be305bf553e27fa95ab9bbc9bb417f4c8280f13538ff3a2846305aadb9a3f55adcf5ddaf38a4db7045e70690370ea0be76d146c8b41	\\x008000039cbb0c2573c49d49100192ba089286bbce1f96f62ae125cfd28cda1e7bbefe75a2678a9779061817292af6e2ea4cce569e59c5a83b109d091a267113694af0267eb4f9be67cdcf0f2a9a52ef6bfbd8db2811381e90fff7a29143fbe89758369d39ddc34f50057eba6224839d63b5c424ad6c3fada61d721c17180c1342678339010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x34f143c240544e74b3a6d72c125f821ec3bb2899bd7a13afd25d8ddbeee9a1f546e0e4438257638b74aa37df3ed8f845ebd51c29124c0cbf8c2ad4cc014bb304	1641789212000000	1642394012000000	1705466012000000	1800074012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	20
\\x30b070915d1418a08c941b7fe5648f55a5bf2af4ac397cc392a29109c2389873824389857fb49276e28fc83347715dd837896441a1884fedff383f517b37a069	\\x00800003bbc3cc6a09cd235c097d17152ec8c5bda97c82a44ee33332fd09ac13c3b45c64c987c7b2679b6166ee7eba556016350469cc271b491f6f5840aa3ac4449e74227b391b3c86df5768044042f28f587e70ad5daa0d0a975994dd52579447ab2b93e7b8d111f130e05ed6e6d2e76d81f1c30829d790518efb19ce98acfa67b38ceb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x41219a9dba43561265c0c6b2aa3e13093bf412b2c6e0640857400917d1c9e12a5fa67cb0671029965d9992b84b1772327cf7aff7784ebd21ce2fe4cf2ee89704	1617609212000000	1618214012000000	1681286012000000	1775894012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	21
\\x3088a0edbb2478946de33c5e86d187784f7f06ffc6e0d7b0c66f1f6725d92a060ce54cfee14c43d52a6f9e7c000c6fbc327c95c4fac804ed4b5be8bee8649d60	\\x00800003b709987f96db6e422301fdf7543106f2112d786e2e4e8ee2a38295fc78f8e4993c53b1e1228e1b2323720f3254d84bd30ecb769e1cd131cee8515494e01bdd354dc13168eec2899c589ec610213becd3a1a48a7ab8d313a2bd42e2f9ca59a058710c52777166949d18cd1511b76d6db47e48e8370cebb767cb27fa3f0cdc76c9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x35a4000ab20fe19283b5d449ee3dd714f229e8914469f7980a874da0f04f5ee07492d11585d218b6b9f2b5b20ff5544f60abde8d1f38828f806d99ef61b6d705	1622445212000000	1623050012000000	1686122012000000	1780730012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x32dca9f415b1baeeb754e5b44f9d0496c0f804054fce591939775718e5245283a75db400bce0ef94592ac77ab568530213bcb7d7fece4ab83e8c2b1a5f9dffa2	\\x00800003bc39be0fab2af38dc5da86b630f1a7c75404dd0b25f8ae0d3dad8d818ed27d3ba4275b72e4e8e75d603f3c30d8d77ee18ef42e818bf8b692e76d613a656a7866090c949f72949cbf8ab5c248769061262919b20cb92b64112096ea526a89ea06e332e1aabb5276f7caf22fdd5119d02cda577a4aefd3fb6e69c3bdb5b9174c4f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa88c644c61da6e2b56234efc5c421b03920b38f0315d19669ab5a2c89859221d83b9d3bbee73314bdf7728f82d17a91b23322d4f10421ebf729e4327292b5b06	1627281212000000	1627886012000000	1690958012000000	1785566012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	23
\\x3eac833aff8fcbc206b3bdd0ffba77eac0bf992447ccd7402ccf319dee8ac0f26d829dc48e3d6d2f501de6b81b3fb5c30aa9eb9ec7275ab04b31152979ac8b94	\\x00800003d6e99326689a56f2dcb32dff64f180c6eec9cdaf43a9a8878b36968796f7b5287e753863d47cc891ad632f41d8ffb654045304be43fafd8ead57142eb1a7486796525e57b6cd9d6f61d4ef94b5d630b2b80a4d4e3795537252f52230091f6f66fa8ca580080e28de3deb89cfdca9b3611c7dad33d4b230230abda8f7d09a34af010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9a663567cbcd57a8856e0e359257800583638465a8c5d2a4977f075c453c2ba65d75b1d9bf9da37f95b373e6d74566004046c9feb5e18e1509a29113e8fc1504	1633930712000000	1634535512000000	1697607512000000	1792215512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	24
\\x41081ab42a48b1007dd447311040a634675ad5d79a733a440d0a832b88ad11f8feb6f7ca5a7e6124602899d6fe692ee857f2b3857ce212ee5b6ef98eb87a4db1	\\x00800003b5f4270a93ee576bde63771820dc6ccf397dc7eb71b15f65c246692702d3dc4c8fc92796f6b89694588e613899f797fdd72bfd31bfc5e91df50675193ca134c6a547fc7a084f5e22df8cbfe21bf0ab609b4d70801964030cab6bd1d5d90ab1f66d9bb60001c41b2acf495767cb7ab31545d1c79c423a0d507e411fca740e10c1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x720934abdc876e32b0a954a2d1b1737c7a7a2681b61b18f9abb3b34d68c61c9639b035e3aa4073077eeaac0625b1724f3f04768436a46e35265f3acd56d81b04	1622445212000000	1623050012000000	1686122012000000	1780730012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	25
\\x41607c32727ebca6f72add7e849c921e0cbeb0030ad6843bf5a9a7130c1943959b844244b8db2f91530aedf49b28ea993d4ac548ff46a50a2e83bf13827b711b	\\x00800003d446f25e68da2f1fd27849158a03fa90a7c281d05f5b660442760b538dfc54ed935aa4a4528ad7d28e6f4574550384c0becf5c1c9ec2f9b4c0b85b379bbed2fc5297333c7127e7a311b0206081e36a632f69c4fc19ef84c7fcdaf6a99b5a7527798d3fbc61ff199fdd4d7ee5d6926b7709861026081360e39ed884284384ef0b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4095a125834eeaec71c634b5b9ccb78290d8b4187f793c55f81c814c456f152448bde0993149f03b0dbc9ba5e260340037be80caca6d5c29eb0e069be2511d08	1614586712000000	1615191512000000	1678263512000000	1772871512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	26
\\x46e462f765e8c4fd7bcc80c842f4b849a55909e7a6be9b7731f204cee5ef81d16b388bf230ec5b755c6c6dc42e43ff43cc0018721508e85cbd206e63482688b5	\\x00800003cdbad387a91a42820c69ed94c213729dba91fb4f9b4a2ccef6d65af4b1cbf075702dce2c114d19cd5333f5b52058be9952906377926940de1083342cf13eef791712463a783a2cb94c29ac2e2f8feda33b2a8951607d5784001e1d96fc8d9868de047b6e2dba2ca1aacbd9284c945d1d4134a5c4773eba0896163f4c80500cb9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4ad9dff4cf020e60ff6f6494dfb6355f7567edac3edcfd88555b4291d4841d1a44826160ee15f26331abe9197037ea589e5b61e30b653679fb2ede907d3afd00	1640580212000000	1641185012000000	1704257012000000	1798865012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	27
\\x474cbd7b06d85237421ca3005fbafb48d07bdeccf78d133a9e5dfc086e9688a9e8d3f775271d87199d9bda669a49b8c6a2d523cee6a1e5df770c53c5c1828347	\\x00800003ce8a0181e8cc231f824bebd635c45cf913521364b7bd3a698feced96943b0999da78a7e506cb4a3c87d7896b07a39d8a53a973e44156fb89eef8d6320e585a08c46e6905b0334c1847c1839f372fd3b4eb30ebd0a32c818659f3c4c9076328c7863c506bc4ac61df31d486d8f6f4fe67d4a92fa6b0875aebfc52f39541b534bf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2be6d246341e78eb6dfc81a69d54387262bc346127b8aeaf53dde7ca7d020d8ad219127202a0a6f5b669e165d9f0825f97689f41fb661ea94c2f93795ec22606	1641789212000000	1642394012000000	1705466012000000	1800074012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	28
\\x4748e26f46093bb691b39cde8e2b640e23c78e9ed2774d1b1f166b36e926e928be0529e6eb5ff273ae748f4e3d860c0ee1666f3f4865ae7f6e51810543a14b2d	\\x00800003d35b372ebb59d2e6147d07cd9c0f197ab8e33878244c6a5072578e2768f8b71687bfba7562198197cb09ba766e9634315ebf4834be17e9bf08ee0afb0340f64152283f9bb04502aaf318ec0bd2fa55bcd8a6d6767d02cd1b027b0d8fb998db61af02baafad568a3e004491e6f7ee2526adad55fb8188a7872a73c26deed4a2f7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xec6e67d3c29e9b640db24b2d308ed3b904699a253e680b05fa8e27c3dc1a9c806bc3c540acf57925e651cc7ef3f46c5184c0adf75b1df78f86a943fd30152403	1627885712000000	1628490512000000	1691562512000000	1786170512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	29
\\x4844a108b41efff7b0f7867c17b234ea9a47d6363ba2e78e4c225343569d319ff601489ff2313133952e18a005c57c822aa05a78b3caa447c0679a1a2b8a4809	\\x00800003b175361e4bb87265c4bca84a6fba3088f7cc4712134822b470807db1e9f9426d426f34eca36e4cf206533db7ccf3757cf7236581392fcefb5660fa812e7384d4bda53aef2fd9905d3b2985f0a038ae7cf9680973eecff9a1ddfb509c63298a2932c81bb5d4020ff16fcd4f911726ffce0e2422077c83fca4fac18aa62973e427010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3d417a0d489bfb16b6530e95f6d7911a02fae7b938a8485c01a33b6062f8564914ee0dbe00d415f341b1efd242face8c955461ebe3c6bbc26a56963bc4fa5d0b	1617004712000000	1617609512000000	1680681512000000	1775289512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	30
\\x491c8c2adb816e9dc30d157e5d726b85c64884652158c5c1f30bb208ec8f0d6e5756c270998f68621079e2523762b783e83bf3ff0d38b1900d4c251a2996d2fe	\\x00800003bfaabecfa6232085a6bc7dfc6690156546c64746cf21558ae3e9f859b21957141067c0f3945019242144b88ed9c99ca0c3e68bf5cca22ae6ed4fa4b8aec63e07a4b6957c74e8b728cfd763c50a8fac3df45fa9616bdc4bc4cd3e0775d13a166556998aa6add5b83a733d4d75a3b6b1ae074f794f75f926ab66d36ed4f09763ad010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x10dd7001e48feb5412292c24fbf8f68952d4604dc3083421dfa8166c25755103162247f9aad953f55139e81138a0bd8860d92e009231c30a65b63226f788060a	1618818212000000	1619423012000000	1682495012000000	1777103012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	31
\\x4ac4a646538181f4d5289a314022d6fc1d92beb2a14ba91e25c5aff34f96695636d94d43580bcac4e0c2bbc874f2553577c1304831f5874aa4726aba24deda87	\\x00800003b1d12f1c5141b387cfc88212f65d3a741ec69b774f2de0b25a5b208712d36835ab002846802e924b1a3b19bad26939191779e9ff902f8d50a0a885c5fec44d6a265be48a7c1d8b2b2fcd60b44c48d2141220455a5052c64c7ea7db18420e260c9776e2dfb453bb538bf52ae010499656407f5f3f88db9adc817b1dd6749a699b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8517b3808670da41bd84f00ae1fc88784154263c3f863191b8d1308f569a156adcb30bb8cf6edc4c6a5bf313c64163f228a294ec9a2fb5b7049e22313c190f0d	1636953212000000	1637558012000000	1700630012000000	1795238012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	32
\\x4d2c63791f5c2ba772943ba99bc12cd3e1ef1f4cd77d9270768ede81debad560db2977dddfbf616eae24164a49464b7ca4f404e327b18936d688216d0c0ef72f	\\x00800003e92a00f231131b709e60dc5db751bd7b5c0e04a0d1dba26c1c5feca0e4f6ada569cc51141f064d64e47020885b3f3999d41272204b0c2f95670cd15947bc24b5232c88802a7adba5975dcd1c3498a3948ac18eceb69f80f513c4d86d1368ce434d2062ab988c9bf17055af7d89fd24cac6ae8247526d9d749c60c4e807a4e651010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x55f8e9830e793e10223bdab0289fdb3b53554a5da55d6352fd981f037a65668d3e888771aed225446aaddb6d4db1d0c974dcf6e2e7b8d3085768ce7dcfe35d08	1610355212000000	1610960012000000	1674032012000000	1768640012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	33
\\x501061918a36c94dbf194dbb2b2381b0fa1389b5cf865504ca80fd39a8ffd757e7e37f65a2339e0c31f45553df356469d88a3452cf48f293eb7f85d6681110b5	\\x00800003e7d634941dbe3ed382826addad527cc435c007159503c18310da78fdaab95f7195cb61d64b4380c14b234daf276c3e7c3a39e01242615b150a24e4d40acc9d1b431b9a6f5cb1a768aa862ee8c94ca2ca2097e7cb342ebe8262fba647073e87312bf48d1b0a7de29c0aa9d162c6d8038587992a6881ed81f0bc85049eeecd9871010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x718d2faa1a296f691c7c70922808838195fabd43b107ebc304a6a3f7fe0fad57485fcc86ded6cca488da11b8d6d97eaa85eac18138614a66a0605e1d69a71d03	1612168712000000	1612773512000000	1675845512000000	1770453512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	34
\\x53f824efdad9b8dfcfc2f861b7cc778710a4c2fb72c2a39f4422bee8fb477bcb07c5326749c392bd23020e5c8b5a17fc49075a96f311eef762f4bee8429cedd2	\\x00800003acd8908d909280835188631693c0b5a16416c886b83ab10078aa322efbc8a849b5dc2403ed225830042e6923737713d389aa97579f1cc09c15685294b863948f5acce8b340df48b0c236fd880cb89a55af5f28985a2cbf70c36d234ea9f01c8f3969e584b45c5cd81dbcdcc885a61b0730ed2342f2453236df5038708b03dd11010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x98d18e26bc353cef28fa7498d4ab97b1597f526060120ff844b38d2f07e5304732ba62df0bfff76c24f757863ecc8f863e7a729675d22716065b6b0ab9f03809	1636953212000000	1637558012000000	1700630012000000	1795238012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	35
\\x5518274ae100fbb6e71c285c29b58be910dd192cf0dafb3846adce3ae9afd9f72845915f7de932bdf5eeced358cc5fd65b745f67d7ac0821b8c2750a61270e09	\\x00800003cb8d9c55c7361a28d9c8e5f16b833249906bad6e2852bd79239b4082a94c1c9d75008bf70cb7784cf0b06648df9388d55ce28fd5eb618bbb8eddbca2aa389dbcc7de1f1c2d37d7aa786bef4e3653a0aef184bde9fee7d2f0304dfce9bd66a92810ad1c3af4c247bd8f7fb05d982ce6e4b7360db00d22baac42924dc410a736ab010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdad3d062be3ece3cc01161cdf9cdfc941b13ca9cb181625fa4e18030bb8e5eeced9aad26c5471ae5a82c92ee7de5ea36acfbdda57ca7f19cde5dcad1f54ea707	1631512712000000	1632117512000000	1695189512000000	1789797512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	36
\\x55f087ea16afa163b848866a4c69e04dea9c1fe9fe7ebd631c65dd1c9c4c4f490ae9049216dac271fab88d6876cfab22150bdc48a4f9400a40d6df461d781db6	\\x00800003cdb056bfbb55e4fcfa9277e6a88f3629969d54507fed7ce8218e032af68dedb767e77ef109d6eaab00bcaf609cedc8ef37d815a1331844729e18dd4191935dd0547519fd3882f76fa2cfe23f7a1ce21377ed75e243d6fac18d33c4e15689c281ff3e673a16b79661bfe079c521871d1cd9f74b80b04f57318b12a6ea1c757317010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3631094bf8054e045eb05c184865364eb994a71329cbc28c2ca709d01a3a23c977fe8e229a8d9e93323a794c798e2ef25d27b2d0cf03e52e7120eaa88069c70c	1633326212000000	1633931012000000	1697003012000000	1791611012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	37
\\x5538383852cc2fa6fef3d2b64e52c14b97f8a41ca640e785e3fb3acd02385df055fb59c225c089a368d6919962441f8080674b0e903147751759dc45c320307a	\\x00800003c38f5d8fe708b9bf084023577eb5e6b33cde57ca99ee1e414ab5a72a798e9b9539c42c755b2f3c9a46d63f1061373688728d8d1a55d102a480924abce1d1cbc88ebbb040ca964ed7e227fe8c0b09088e403abcafe03215cd1bfe2f42aabcca0775f4dc2a97f6515fa5e979409f908fb015548f284fb154a9ec9f6c03e7cea6d7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1c3a55cf449002ccb9ec716553b842e9c6d6c60af55895ad206c9e022ea45149eae08e77efa36d3b0778911359111dd49ad9680efca767e17fe37433ac4d3802	1626072212000000	1626677012000000	1689749012000000	1784357012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	38
\\x56508c18a1fe420bc265c23269b7edfd01f1920767f3febea2b304da9e545d7936eb0ac1283fc75f4fbd8e3622551a5ca1f3e1322cb8e1a83f190f344b7b5e6e	\\x00800003c26c55be98e9b07cda9c0a6a6c118b2ce4cdb6d2d33ab9428c193513acd7d9705ee490f9608ebb0bf01dfed5c1ef50016675c4f9b8a1cb42fbf77763ac3ee9c12d6724cc186b427b33d605ce52a345ec045145ec0ce73818720967a21296d3bb2aa846357679cf66207d3e10ab4cb78b54486a4c5d8d8264847c8a629c9096dd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbada6945b6e74196675317dd06133535fe801797a624a7c0fd9eaff56d6fa693a5e6fe781b08bad67fc61ce6d7bd63e7b3770e0ad8fcdab9e5de81fa45948109	1629699212000000	1630304012000000	1693376012000000	1787984012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	39
\\x57b4d3a5432b84b7ff03cfe306c1e0c8326b11e22caee9abc6c3ce08aab43054d7a4f129f4277c04b6582fcb4aedda92d112da44c68e3b0a24a67405982ca9f6	\\x0080000392c2b6eb3cc95e6a50cc1a231e4e137716005d0b926fb26af71bce6093b15ceee5fa6de0c04d5a163cd0d68111fd71ff708c2401b3b410cd6ed8416e1cc8d642ce2d744d650e2ea12483b2525f959191eee3ec4b12fc03c27ae3b24b1d39d67042ce0377f4553d977013f180f983c9337c83134b6369b51605e09bac900ad769010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa2c4ed6e4526361f3680c483a8dafcb96d249a1b55500e09b2e4a885bc179a07cba65209ed8a0213f7a2ab0e71f533f4889f250b76c2f61f1b34725634257800	1620631712000000	1621236512000000	1684308512000000	1778916512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	40
\\x590cc3a4b9b2b797e34ca8bcc3a8e88faecae9004cf63fcb7821b0a8201ea7f0e5657ba1e6ba414181cf483db69785d8ff0e790985a598f73e10e84b99cd7f29	\\x00800003a0a5b31fc64f24cae0525c15bfd7af4cea9a1d090f5d085cee7f5f53718c4a66a8c951e9bc5414eebf7cbbe6a6c0ea5f272b64ca185c684050936b6f2605038f74e994b706291a26b943ff89db772ecb8b67bf79d3097f8c62cea748e5c56c284e960ddf5b4a924d9b67642953226eb7cbceaa92e842aa20727d1c1dca8dedc3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb032e4067b794a88012b62ac8aff04fb7c54cb601f87fbe583c73a480da0da0a339c3c11a7854cdac87ac86fb7be0089a998f365f263e7e8941da314ec34450c	1639975712000000	1640580512000000	1703652512000000	1798260512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x5b74cf519eda62e5e5aced5ff0ce10ca70e8837c5187b518ca6cc1fd90b5ebd2c54bf686522cb44940cc3f6de4ef604808d8b7a4d88928a97c3c322efdbf2498	\\x00800003b0f6effc8377fbe585eb2db537a8423e70fe4eac5cb51cbb8f770308ad5407fbed7e0e2b5b9d1d9d4e37b7cb8a2cff992fd477f7bf420d3687f62225d537f6345fce010f5f8abae05d5eb7be57a47add820b607dd6a4d335afad6466b03446f468502761b017593aa53d8b8ddbf27eb9c9c13fb1b7d3c02b59ad839c758d9ef7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x438c6a2ef02ec27d12a34bcf70df0882b8449e35dd1e192746e8884f7303afc5e70e1827f6b91254b79345bdf1e5fc5764d6e4d467aead061d92f6cb0dbdf40b	1617609212000000	1618214012000000	1681286012000000	1775894012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	42
\\x5d1c68146e09222e9eaabde1d66587c846076ea0f807d23fa15839b7da29055980394cccede9ecf0f64e2403d8509a1777ff659eaf92c7fc87884c499bcbae20	\\x00800003bae1e5eb7c949bde0fb1d10fd890494576bc25dcba378170731c44f6e296af6d4c38a7e0f7ee0d2a52a04c409b6daa85b19fe848a12bbf769b283a0f1320e75ccaf423612771cc8027b57fa13c9856868563c91c17da894f124ffd1cd28a96b0a3cb3032970d954e80248502e5a6c459da61dc630176ec036b84677c7a368603010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd985630ce91fb509d71db60e2fdd612662a0a4a853d4d635ad2d7c234b8af863ff15533339cf47635cd38243fe0529b1d23fb87b89e284cf6ad3b822003a9e05	1623654212000000	1624259012000000	1687331012000000	1781939012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	43
\\x62a40bdc9346e2dc82644e678e247f0ba5fa6c29755d9db51bc8b0c08e213f1a4b480ccb6d769acb8fb71c7570581ad910b84bda8953b04c249a4fc7ba9d30b6	\\x00800003e6c8b01eee8e979f0fbc1fb82e71bdc4bb0d16d53ff1736a37110e5484ce4ca3a18d104ad4f81cc5c0d076d0db70573185d95b3aadaf4c18692c6b72d161675602c4676d2f2ef92ccb1fe105875a0b3eb465f18533b0987049d929072abd0ef3964862f70c2393e57c806c84008f004821df128d39268cb50183843bba0b0f29010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcc004b41581a988b67dc851bc81be1145a526cb8086e5632dde2042976371784ee1f130a7b42641303781ab9a6850d4f8fd9e385d05fbf5dc01eb60e6f183f00	1634535212000000	1635140012000000	1698212012000000	1792820012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	44
\\x6374424e762b65c1508bac0b0ddf76036bcb6616b8651b7df1806b38b0323fa39ce7612dda71753176331c980b5fac2a1a85ad827714d7e568869d62b62c334d	\\x00800003d63352d672824476b81169036118fe490481c368dc2753bd555c449a08cf8cf2997a7dd21a93b89d5635b6037f3cd9c2265425abec41bd42fe5c2f571eea8d87d353cc53a15edbb5498208c6b646e24286847c2c8627d86d372d51bd5ff7feee2e8587327028516ba10f4fcd0ddf6cd00e22534e57600d4b488033f543a2ebe7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa59ca8efd195cfe2379903480d921f36ce0912a4e988096726f2a4bc8dfa1c1f6ef70058502c9f2c5d7656f0264fa6e0a3667abd5a2e0618bcb3e78aa8615a0a	1632117212000000	1632722012000000	1695794012000000	1790402012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	45
\\x641cd70361b582cdacda968fafd424e1b0b89198f23618fec8f470d1ac6e6db2a4147f0245b538e94f8682091d959991ed3f8eb021f823df68fa504e475eca6e	\\x00800003e2df3807dd7a894d4654f3953fe21c6646114305467d80a2f78e5ee55b027232e4e5e2796bb49e4d01af5a12111f66bae30d5ddb6785cca2576db404cf955118b44cf4967c1c0915f05cb01ef799048ffdb3f849c5d7718215ae45ead9787ec402a61a4bda89e958999d513397d128bf698edd8967b6053575725ee55994d063010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf21e57840cf84bcca222199081c407428c36ed3fe71632a1a2681920984227bae6637121f746d310b35429fb778af18ddb2649ddb9e7c927e30ef4439207a107	1633930712000000	1634535512000000	1697607512000000	1792215512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	46
\\x643c8a4401071bd373ef6f8c898153afeb4c38de9633fc47c7118da4412779bca7cc140591238af00ba19960755f614ea6c2095e7fc2af9d7e70be29e0799d43	\\x00800003b1a8ec5e268aa92e1f5a477d110a834b79782c165574d1a02ca41f22c428eebbf54c6e2ae35ca3c4229aed878f2551283264cd84435c09401bb51c7f86b5af098268cf566c51ce21514cc9250886c2341c8fe9a3c8ff8f0dd3a0e8e05174ab62f64fa9aefa02448c76b21fa953776a6a1634dd2f04acf527f97b4747ae40a7bf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf228550c54a7eab122348d44190f84fe4be2744c1f652efeb007d9078782b7409233c505dfc845971a217bdc911bf75964ccf8f3c14266f7c9ee0d82469d260a	1624863212000000	1625468012000000	1688540012000000	1783148012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	47
\\x6af889c8113a87b95c5c2f4d686f27f4935ea708075acf9c1d683df81ae2c4ac7d3c3aac642d7234a219febc8ccc14a02dca7e05d4e85cd300d6fde6e5981dc9	\\x00800003c86c8ba47fd1d3e1150db6aaecbe345e1a768a8f4689bb01d3928f4089d123c799aa71dc3435e4c5236e0acc860f25d5fb5fcc9e369875516a6068cff25490bb5000f925d5ed4a33cc5c916c84bb00f52a08f5e9585d5c3f6d6dcc1dcdbe40425f6f5273a8fc9370b546cca3aee72c43d344199e67de1eafb28c436b134a8537010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5ea7427e356443466884a8422978539ec98a7a37fb0645417d3f4ecf050533cfa81bc1e6fafd8816cb3689115690e87d9f045def429720698ec344e392f08b04	1621840712000000	1622445512000000	1685517512000000	1780125512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	48
\\x6bc858faf80e6ef0b285d02bc95b47a9e7c224631bdb224cb31d879ceee2e7642abb72e8a0121a559b3fd9284d1b42b833cdd284983789562bbc9f04b0ef3315	\\x00800003c9c89550b90f4b311648f6d6bd48c9feae3633e2a8b14673e6a693949a2a2e617052c8e0d398ed2a81ce573b8f5110d16a825c1555185b1e91ff956d528b19e55a57c1b424aa8df9d6ef3e96298e3e9f117b7935a851ac257539e71afae5283d7c46a65a515aa8b63ea6026ade3e23a40a19c3603a0c9e62065b704c9109f8cd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x16f699084f8956a0cba25c9e8059888a38a4545c638683d7ae1cc82391e57c88f776d89c93b74a90dd59ae631d50ede4cae3b3d850689b0400f012d1a864c105	1626676712000000	1627281512000000	1690353512000000	1784961512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	49
\\x6c20a43ba5228e677e04e7c63b6df3ea429535f8a3a8a962a078f3a041bf82979439a507298df284a6b6442ba767636524e810d9520458411d507837b9c2e051	\\x00800003b3e9d72f6022a51cac766b6d4f9cb5e0674f56748e47250a1bd8206e72dac1060eb66d46d578d46dc7b9da76fabbbfcad81ce5e1a8cbffe0be276166614900903e77d7894393e335aafa4f2dbc49af27c072e0db2e6c84bbd491bd3bc18ab63b201d86fffeaa7b133eb06341da330c2d4c5f69a611eafab96e8badbdae1c8e1d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xeb8b0c2e2d38331fdfce0472785dc31723d159a1c8c6e090aa3359de09fc169250e0ba9fbf44a910b7a9312afcef49049fa6d5315e574204a995658f5f9b290e	1635744212000000	1636349012000000	1699421012000000	1794029012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	50
\\x6ee8b6d2816461a8b8c3031047c92af4eaa8a8b9daa7a241fec89b1eefb127163a21033a384909b72a8a02856403e15a06a17f1e02647d1ce219a26ce5cd2a06	\\x00800003ea0c7991870261c16f1291325c0d5fe3fb2a350056c9b518d95d3b6daf7313cd11902544bf5dbfa6df98038c6a7e7f67be7ffce3e5a53d651fe0c10ebd3f456b35fe5efd3fa9bf9aace453f6e39b8e10af6ac7b94982876d73f76b963c43abfc4abcdb8c1689e37ba4d9d421e3c09505cbbff634cedd5bace27a3497601da767010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6548252de1523a858346a1bc66d9acd0498a045e703bf2e28bf754c94f96bb95dc1b78137d05af6a95b328776682f49d07418f9911fe2608d0b0a0b43c0e8107	1613377712000000	1613982512000000	1677054512000000	1771662512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	51
\\x6f386e37d5d31a95bd4efbb95d52142ee53bda02bfb2221c38d63830da3b4234c16bddbf0a239fce5a23954f1f1dfe577f51a6063bdc1827ec2013b601c71cc2	\\x00800003c3ffcd4ba1e6b149738d03554067d0ce60b90ef041267e866925a90c53d3efa9b4d9fe37e2876598b41e1ccd51a8efa88465de758663343a20b7ef241c9054a45ec27782bfb0b4727fa540f9ac2c31a849e72dd76d91422a77cf25fca4477096c8c8d26f802c589ed8db3a74b66be21551a85834301cb4f774b56704a329aa17010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb7725e7f28303d3960f29260f96aa377343f750c921d3587961a08df9505d31902cd2fca13522561d12fe5afc1542d9582f1bb5eea8b3efeccb965b3ed93c50c	1636348712000000	1636953512000000	1700025512000000	1794633512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	52
\\x6fac40cff17d08d5b037bbe6509c92baff69f2b158bbc6cb1d18a7f69e9d9aceee592e903e5c6ca93a72cb6d78aa1d96822ba345eb856c4b4f60a496d827768a	\\x00800003c54715bbe773d0186afc4de990941d9c6b316ae60144a66a54723c6e492ea039e8b97b101a215e6469fd2c24d49f4e04ff2cf43a71b2afffe0d7f68a80eb3e204e8dec53aa44528ac8abac5dd2776eebc066a9a7a6a0baf0e7dce1a6e1ed501308e4a8281bf8775ec7e2c4a673be0d9c8018ff6d9e2153edebf7c5ca773c7817010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf77db5977f399968e92ce93194d69c00b8dd4b0c2cbe91188cfde68951463d69d8baf0d5fc3c19e8e261edaf6c2225c5b935c3c7e6d7ef587ba24aab74f5b60d	1624258712000000	1624863512000000	1687935512000000	1782543512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	53
\\x726c4702e7bab847b1c3af4bfba39cc3cc8aef183fd93139bc85b0de9eb0d18cd4d418ffd5af77d37f2fa05b216c94d32b646dba10d49baa8e53319572c12417	\\x00800003cccb6268088d5f2e637fc85a9e0eba5add4ff4b2e671e3155e540f0a8b763034700c0097f5bec01a49f32e36703dfeda237fccef8b3a1f4cf60f08c20d87dc10ecc54e4023bc66f539254958afa58822e267aaf39a7d74b1300b9d9d3cfe6f74775b5cce1e8ed32b80eb24604d0e4071ccb813f582d6dc930704c29f1897d389010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa95ee00bd59827e5c1641d625e07524b7838943789fa33bd5335adde164aa26dac11e662787e29fb633b9d82e7c2ae839626114b350f6ae89584285b5f9ca70a	1618213712000000	1618818512000000	1681890512000000	1776498512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	54
\\x7600aeff60a28627bebb5a5868ebb1901f1dbe1ccf2561b306502fc2f8136b12680607069947e06dbb855e0bc779044843389399ec4e01c1bf68866e9ae66925	\\x00800003b4f4dfef5dbdb5d401eda9b92eb82110a0d09e6e39b4c9cfb887a1ff0ab0fe02a6b31f2782daf0b730d5fb7263aad059eb690a6e57f37e11b5e9236c8003b9ad583d0f52ffe84188e913ec4d13750e04796e4fa692ab4f843f9ebe51ccf7d41703c11895f9aa295350aa25ecf0ad3345f6cacc351c6d728313177361f540d74f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa54c2b4b2383c70f93a1e56cb354663e1510793566c1819006a2fe16add71c4346a761fe9411c4b4bac88202fea503b97baa87e62425542492a186df4bfaeb06	1639371212000000	1639976012000000	1703048012000000	1797656012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	55
\\x79c0c803f1acd6bb55cf38c489f44d664dcc28deefa7e41329141f2ee7d4831434e4552ff58214d946209781959ec11be368a127b0b4ac76f8b1f86aed784990	\\x00800003e6e3acd2e170d3bd7e8418fd08a494f525435b0134766a4b090d0110cb63e75bacb5f3208e6bbea80f0a4db6342d89beed8dcfbc874a3dc3eac039c5a10c577df46e40c30aa67d575be14d4d0d0ceb124882441f234f58bdc698fc7454ea09475dca939e5fb73e2d4d45f323a384ea85a90d7287f0f1338468d5525c3e4e3aaf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf33cf7053d488deb04545bfc9b727c86dd08f0b34d0512eab5397a0268632df8b497ad5352f84ed9ffe384772ef893440885342fc9d3da3a9114e0a59dbb7c05	1638766712000000	1639371512000000	1702443512000000	1797051512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	56
\\x85e0a35b1ac99bf3a7840908e11a7df2aad7309c6bc5f87c6d201daf852cef2b5262781c13489fa9a5e12d84fca2d99626bca60711f469175884946938f37359	\\x00800003b50e8187fc80b19e0994ba787d429a54d555a7c2cf88fdbe83257bb7875e568cd447cfad4009c470b8decc7c0c4e54f4217dbf386db12d7f80d6c8ccfdd11343e45bfd21753bcf7153c43657ed859a029679bfbdc226cc5dfeaea7bc5446b80632631e730554866708dbbccd8f7f71fb6b6e33ed172edda8c1d69b4987931ddb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6318eb201553d2e35142f02a07ef20393daed68bfa9cbc10f36d3d4d69fc099440aa56b9ae42c6d63cac8c0c5737baa736dda9c936ae441568b6e9ab91641f08	1630908212000000	1631513012000000	1694585012000000	1789193012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	57
\\x894866e26133aff40c7ec0ee3bfdaff7f882d416810bdd6b85cb641e9f45f191b63b7b35312f2576bd221a63af0cad5f6e79715b4a29da704dbd6bd4961276b8	\\x00800003efae90ef88bd0c97431d6d546fc78c532105f65b7c7cf33b99fc7b93578d91093b16722f6928927904586dc586c26a6a78e7356fabb15f683e6a5dca9c3d8ed680168f20674b2bfd70eb4a7368d2e93e634f31c7cd98228b2ed9b3add5f65eab4f548bb847dc931285203ee688e7f4f4caf7166828324b26defe4c4567081515010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1d9ac157c1013621027e5922c537362d6472948550d0f0917d57161c702cf99f6de98292bac76ed1e4739c4f5f8e834e5264dd44e347275a524ee9156feb5602	1613377712000000	1613982512000000	1677054512000000	1771662512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	58
\\x8c186caf5824a497ed0166347a2ef46e657bc26d050a0c6d48a2ad4ca2e2e4879d599997a86d85fb1f16c0c6fb41a867be865f0ab9385f8d8938846020ff2cc5	\\x00800003c05ef11af9d32d2c81eb846e1a4222e2b52083c8838d2e74fb7c72d47a887362b42db7ab2219ff3f4c7ffe2b8d1aa8d5d2e79c0b232aaf186142731108029ee8a784edac22da6070082c35d2480088b76e5c4945b3e33963ad888603084e22f18a775b648bcfd69ff32e91d5211006efa4dd8d1e7d075fdc666a0c8526a48373010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x24ac668a160c8f8795293aecf5da8cb08e3a7a3ac2a3f5e12afb1412a3ba98e24e497778da6a11ca0cafdc712b9384f74d8bdafe6f381a97911df810b55c1a06	1622445212000000	1623050012000000	1686122012000000	1780730012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	59
\\x8db8278c404b7a956f2bf1aaacf78a329dbd56554e769144a0c4c1952166c15c7175cc140097e79766bf10473d4443992efb36bbc401586107fdfdfd43f53e06	\\x00800003c08437103826f34ecf6c490901868cfeff7240432e1022b0882d4b3e879cbf631b362a7ffc49678574058993913322ea8c3a1039c513b4151c55fb24bbfea4fcde4d9d6092627e0250afaaa58aa2a082f5b3f403539ba02b80d9dd1697d17903a9e3b4979860634ed4d552e258292a54e70812c86d1f085f891dc10f63d35053010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa9f95e1c90e5e3262973098b48c4b5deb252f7b09c791e0de8725afbad0cd54153c023ce0dbca5a12d214416513dd779816141f1861eef70f1dc4ed88e377000	1624258712000000	1624863512000000	1687935512000000	1782543512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	60
\\x8d34df7b88d3e324b743e287d9abe84e2612909e9e220b9ee5abe64db6323d917ae349970ba87e63c868981cae8b656df9ab02ac2fd44bd2cf6f9e460e350727	\\x00800003e98023e4960e913adc33fccc482e13f2fcd9d17a0b32a94034fb62f9829d1123b31580542ab5739240c90030ca6f23aea40fd255fa66d4188b64060197c71184991e31f343909bdf3b13961798797700ef3e8ff8d47278fbd12b27e84c0e6662975e815f5cda72843a2bdcc77054fb44da690269e8c37a3b3b40b22159a86915010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x600f45386d7cdee811d11e5be753497c6edbc61dfd0922412035bc053fe07fe8c08a4d19a90b4517d232c2a4398c767c1af7ebcb72b0d04ecbf07f79fbbc530a	1629094712000000	1629699512000000	1692771512000000	1787379512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	61
\\x8da85041963ffb874b2734e8509d3112feef14b1389d43628f2b8700c83d00e246f40cb3dc938820aca6e56481c3b10ef8f7824143e82bec527695855dd748df	\\x00800003bb76cae5d902288eaed99b565f446774228ae2ffece97548fab1f344bf0dd266aeae4e470a26286ba37239efa0988c6af85e48cb7eda5ab3a5c8530d621b4aad67d822d6a49590b23844ddef81ce471c91b9b8a2af35883301be129f5132ec1d1699adce342ee58ca69390a7b489559c9a7079093eadd38cc8a377a36853ef33010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe47384b398e53aa6ee41567e4b6baac60385b91f111d7735d478e7c7bdf39e8729f11fd6233700823884eeb1a4e4e41bdb0bb43e60eae235aa7fb0cdbd7d780c	1615191212000000	1615796012000000	1678868012000000	1773476012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	62
\\x8ed8ce7d29e9ccd22e303f208aa383a02564134f3ca38beb0307b5bbc07752f36ac4e5139f07f5a564ca92041ec176f54857a2bc4e5b8815911dbf978893d634	\\x00800003aacc14134851554c31163bc2bb1400722896b8e1b113b595c4e64081c57f99c488b928c655c031eed71ca9ed92fca21877d5d77cd66b63c4050cec9f3447ccb1bf4cec52c86df6242d5e80c6fb53926fee87ec7e0e9a37c84b68d9f3f092eb5efaebb5a3f16c9d887a4fc386c0a156125c46d9da8fd29ebede55366976cdf217010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x60f81a808417222690a00f1fdd44f8eb3e13b60e7e28de05862f423462208d135a7fa7d47a982fcbb5d7d24aa7da0502ba0af6857d5f6e59562a94b1621e970b	1615191212000000	1615796012000000	1678868012000000	1773476012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	63
\\x91c4e7aa7eb88964a8e01288f021f50e444edf931485343ed5496c89ee3b1318dd5900310e44f25ef4852aaf5d1cb2ec56799eeff339cbe638cd6df6a706cbce	\\x00800003c3fc47511e15623b460f484573b2bece699823a514b1b93a2b3cdbc2883c9acf2da6cba1c8a3e552e6877d6a5736d6510e237746f5b47ecc1ff42b8669b8b033ae3a345120d97b25385922b2e222a9a30a5273d067eeeb688fbe94041900e06cf1114f12c760e673757c1321ff934760081b8302553c423637b58bb455c269b3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x19a210741ec3eb456fe51885e6fe044a348a4da02435740c42bd6199e4eceac99d2aa542643599a807e7300a2a5ad06b07787bcdceed1dfe22456cfa6ad9940a	1634535212000000	1635140012000000	1698212012000000	1792820012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	64
\\x97087e03b13fdfe6d6601698f1232cc8360fd189c2cca2bbf43822ed0d2e232a99755877db1bf7790ba25ed8ab528bf8092b09b57e2dd1275ed77e74ac6868da	\\x00800003c1ea39e3773f185f7310e8ab9a778d52cf52a4d5ee9272575a8bc43243fa9fba2f0746e49c9430509e337b55feec99de8db8aed36461703703b003a200ad89b0cd0ff2bfa8b07e649dd74125a53dad2b450bfe19c32a3a9e56242bc033100368b869ce7358b7c22c83244978481f431b39014a5609a37c71c5999ded16738099010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1267cb45120e0982ab4b2db5c539c301249875c16839984f8e16ed64af262f9145adcef836e56912567cc9f04fb27acbb841d00c9133a7b3d772185c75e4d30a	1627281212000000	1627886012000000	1690958012000000	1785566012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	65
\\x985c0b9e9de54775af0b172c51968886157c2f00e5ea70e18e1ffcba3086bb870a52d94b09d84bbd27529121a7edb400751eb22abd8d816c53ed215d77499111	\\x00800003d0c3b35561dab00b890abb7b42992cff802325ad70cf7e546665abb425f2d593c45182de7ff24ed9f8289c41e3f09d591793b30c9e8453f5213214e6d1f3182edcc67bdebb202432a964f4cb8a0f755a4f8e62d04adef86310d53070f91a470c0adf6b1a0558f782d8e45a1afe06b395f2b7c16cb74fbdc996f5933be4232c27010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5ac2834435a74d3275bd8a980dd328bcc3a93937673566c7217c0e51ab24cd3a490a0dc7b83316157eaadd1a7f70c28ae4e6b26d28f11100d7d07386f1ae6807	1641184712000000	1641789512000000	1704861512000000	1799469512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	66
\\x9adc3ed9890b546cd39bb385154abf3f8230b38081e4cee7e8e8dc8f86a322106e94b45cddf9901330f42f80fb0c72735837bcdfd8d1d34b3ca97ab794c10da3	\\x00800003a2e03266485ffa53121140633f429a77360b068bebb7862da4581f4f4e0e54aa4153f0ce1810a282e22e1c8dcf8d9e5df11998c64582438eb4f88c6eb1af7fa8b4d2f732b9bdd63fbff91373804891dd1a5a551e0e024a0f1ca8f5461d8f42ef8cc734e0e1a73e4adecb1c5db9a5b0c36975841dbe04310db784a4a57cdb4bcd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x85d7f065fbd882c17a79dcad107f7ac2cd79abe7c7b2e36c1796a5b73c08159c8b894c5bf4d7057ee1225c4c099d7192d7f4645165b041ad99ff14b9ea943b08	1622445212000000	1623050012000000	1686122012000000	1780730012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	67
\\x9bb034726211a4ad7b94789007f8fe3645d646a1214487fba821ea5bef45ca1ad3836854316cb6c744130c254eacd33db81784bcc8aa85b1ec6a2471faa47c76	\\x00800003d0df79a5219115e7cdf09fad0a240de350a0c8a7c628da80ca069f330fbb399a7109c43fcd8811b2cf328e36dfb97c56fe2eb93ad613f206e1c069265818bbb15a68ca9032f849541bedcac26f5272ab886f0dde3f59af393f692ce9d7b42d08edc366da18c9ae34298f486d8ca7653b0ca57132b50f259c3fa3165de6542b27010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x218e43fd8765e07e20e6e2c4379c07c68d37f7c40d5c65c2f4f7e55895f15687e7a789d8277f9d42ff890bd816e78aad139a2afa8ca4f3adb401082c61f02702	1624863212000000	1625468012000000	1688540012000000	1783148012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	68
\\x9c243cc16b1f1f9175f82bf53958039c40033c4efb99c59a9b619faf52c5e7738ec75e4db0ea51116364e6db806d81be4ab8b853752364e1d022f786bfa96445	\\x00800003ae46e623a83aef4e3b0845191b04f6602565b6b40c5d0ae87d48784aed88c7aa576232a127966db5f4d16a9c2fd43a3f8d91cb7246eb22435eff9e43b0a9f2d38653d9490371289e57b89820d64cf04d4b5eb337af0b514ab6f4ad2ab1b9227fcccf7ccb9c81681b29fb9dddbf3275791bc3ddffed2bf5bfe050ecb809453cf1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xab33bebf178172cfb52d603d5a15f750608a39aa5a252f288d48acdd34eb17fe70a6bd8bc292aeeaacaa91f315443564430a3f3be3f37d27f352b3ad04683a06	1610355212000000	1610960012000000	1674032012000000	1768640012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	69
\\xa234c039eb3686381027dec1297ad1bc91a0e0eb06734bc092cbd820dc6eed38acdea5e7d711c78681bf2c7a454d9ec33315467af2ac8dafe9344384c6f314cf	\\x00800003becd7c9904451964ef8f742ee9f5001bd10ed518483d66888063a25167644d851012dbb7a04efe979635c844e725b092040fdf8a70676c4857c02fa26ea4026194c094deeffa8c0d010e751449e0c46802825055ce2bdc3b1f7334efd1fc2b58d80c19dcb27bd023177947fe8367e39df79360b9b47cdf4fcb8e2106d8272c0b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x55e6ca7a33e4d4a6eb3388107f8d2db538e91f8d1375bf8aaa704e4e08e1e62e2c062e49d0ee30fa05f1ee822b6c840042ba299a479cf5ea6bc5725a91cd3d0e	1633326212000000	1633931012000000	1697003012000000	1791611012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	70
\\xa9001f72cac0b7414ab7810d614ffcd189278b0463d92ecb8738d043d22bedbb730884a5081e360dbca0223dad0beec61537d9fd840d1d1dcfb12e2940237273	\\x00800003c4762be871828a90caa96c4a0adb6fc458b21b17bbff7a0186b8b05be0eeb314954a33645011e8a6d36809d4c3bc6ace5fc784c0cfa5924fa27481d37458533dd3f3ef6979e89bd2625643fe63e44471aaf3143b11073a99fef5454909df02ad8953240e22bb46a0096b6cc235e24530d25fd5ea20a32e279cfc6c657e2819a3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6bd4e79e6e669da6250baf8f119f227d5ac7facca7c3f397002c90f838090e8c07ce11378c2be8ae411a7b4eb91a88caa6e3af1a85d90ef143622478af317e0a	1629094712000000	1629699512000000	1692771512000000	1787379512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	71
\\xa9cc0d2d01f2c27602d73efb1fb283488a04eb356b4c7d895ccc1e4136898520baec64186f9908657aaf115da5bf31fbe7bc1f39c3e3e16ef537e68d7501bf14	\\x00800003c34a21b58aaaf1c125bcae85e1ae2a4605044d672ca6cf0b605cd332c07272d1a85234ac536884cd4b72875faf20e6587c2851a1ef8556d212ba6de6babf5bd291281224044ee719585fce20e15168c4b9d54373281823233e327771c47d6e415b36669174e26af831c14c112fde6e7d4e11ba6dd4072fa13c0a5ad8ae605645010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x00d0807b6ed81989b41a695ef7c7b5ea8d4c90a5a363e7afb27e4d84d17511c3b0cca414f675ecfa179ea9cae9f22a2709df37d6caf72bc1636e5db8d18c2d0a	1627885712000000	1628490512000000	1691562512000000	1786170512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	72
\\xac9c2631410b7cda45445f0059a15870726421e07a542d65ab9d5996627d6e23228e41f9c0ed4f9c8736a1fd91743387712ebf906420e158c4bd868390c5bf41	\\x00800003df9a556c3912468bfd31efb7ad8a2947c75ce9c6ca5470315b034b6efb7d55499b2685d8afced78b6b65cae45671e6dd14e7ec3c050c2a7c805fdbba3c11c96e74fece5ff7d445089297f897a8d488bb6cf1a490f7ddf633dd3b87cfbfe3e0d7cdbe91cf3620bac5b32bb88636b05c1bf71defa99e2e6560d63325976f89b22f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2453071d6cdb2fccfce2f0aff271529d925b0bdcce8acc42aba46a8b0fa81cf6d8f14a5a31c532d6e7e8b5a4e575000958edf0a3fc99e548414e8240ed986605	1612168712000000	1612773512000000	1675845512000000	1770453512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	73
\\xac40cc73203b286f5a4f0d7e7af52ef1e59c26dda40957597686ee872eb3f549e792bdf0985366e50ebbd4d898c24f1d90956ca93e1b7466a15e18e9bf2a9d11	\\x00800003b3159f44bdbc06a4e577d7badffa3c2de4863b2e9a999b624b5b792f8b10e1f0a7840abc23927d866db7a3eaefac7e05cfd5c6d23e6d2d8b7ec8b545ca80a2476ae3becb60d49fec1be15c729ebd124de5a94b71d6db260a7e41a5c0f00361c0c27287adcc6b0866661a118b8c7e07a00ca28a4cba8fed9fd73130b6391b69a9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf0214f53bcf51c66e7c5b71750244d4e59f225ac923d0e3c8d5ba62bcdadc6fc17684ce2b22dd2133e968ea3970e4dad9d1436023e2e3add86ee50147fa7fc0a	1617609212000000	1618214012000000	1681286012000000	1775894012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	74
\\xade459b3cd4979fb59349c81ff13245bb87404aa9d1279940fe60cc9e7af23c7d68655ee97295c81ecde82714b8fa4dadae57e827ddd40dd1c8404ca89c9222b	\\x00800003df0b3aebb744b0f29a589362eacf05e6e62ce7c17d1f5719cd02aa5e5e69cd8246332dae28b3821775b5a0600381beb5984649b04c00a3bb851b97e2c1032943e29f7e0dd375662b43bd02f236312eb6acebe8097745d157e2e7cbac43ecb56dd09ab32f5aa25b4395e51a679aec91e7fb777891929131f838f58eaacad1cf25010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5495ca1548cdcda1f5edf099e8efef418f2fdd83ae9b7240f6abdd879eb4fc1c9259e329b18d58d30b598861e5361340db8efdd1d6a9b1ae468e37dc193cd60b	1623049712000000	1623654512000000	1686726512000000	1781334512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	75
\\xafeccc6ddd82cf7fa53a4b28bed874eb37312e813888b6e7f8d5987d5200754852702f26614d6be252dab144a06d1e8e1501ca9ff1288a8227c511b365ed3df1	\\x00800003bbc21297c091d0f61fccb75d945dd22ce04106553e6711c352d500396bfd6b6a8601ffa6a30c19768843302a4f00526fe665e9fd1a2aedc5b654ae614c1dcd6075a51916f050e56a90e3fd033ad56fd86e63efe1c3f2e90acfea2b6d2deecb3caf1521f9d884811cdf238f93d03a5e1f31a7098c3a7aa5667c74d95508e5031d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xca66cfb009ce7482dd69e09e74570a8b40e625bf9e6e94ed33c1197d29c4e83053c93a6b14f448beb4402b1e9612f35e1eba7ff8bbf9749f68b880b2adfd5e03	1611564212000000	1612169012000000	1675241012000000	1769849012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	76
\\xb354c9ff0b216d9b24deee0ddabf9258d2186d7e8aec675bcdb968521218e53baeb87869cc76a0b5fe3744f246b3fe4ef00af04001bd7a9b1bfaf55bb2e18313	\\x00800003db6c6f5c7ff05a0964e59e28473b5f432a26fc33913c8ca355b534f3810e3a0691e8b4a6584da2394e657460470ae23c57dfc47114682dfb682b22c8dcc47df6756558a14d291422a16a90720b5c60fa2640203cbce7dc9e5fadd0bfd5ac01978549514569d30cb02abc75e4df4a9aef49b283cb408804e83f1a33d00acec817010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x302e030a07757b8c628e57b23d9f07f7f86daf6a1f51d24a03627d0c34d5846d300e340c7d09543153e1f2896e0e5b09282ba3fa77be1d2479e2d75f3ac26e04	1624258712000000	1624863512000000	1687935512000000	1782543512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	77
\\xbc84282598061b992c65c00d254864018aada1e90a02dbbcf7cd15efcfc133a680028f180dd2c4231cf1d5e7e40307c4d5f80c02971816811f7525d52bc1bda0	\\x00800003b967f03946a0e0f5560efee609914fa45ff71f0c9db97b7b518f6b378827a21a6d1e866ead504c20b9070bcf5e0a9b5dc3d3ae2819bde07f18a23d230385d74edb965ccc3d12a04d62041f7f0deab628d92ea7d29c699315cf8c54258ffe0d767cf0e6dd07d12586eaaf96660e952f9c13a8d1d23dc0c0417b19a29444f56e59010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd73bb7563c87a8f20b2f04a61941b8b811a6b335cfa775c8d242a4fd4202168440dbfe76f374ee4c8c34a411f15f70181959a2fc459f7d46ce0ad20641a5950a	1629094712000000	1629699512000000	1692771512000000	1787379512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	78
\\xbd44524edbf1d68bd5011bfe221301c49419c0159d54ca9f8ed87982502cb18d4f333c65560e32dba1b88eec9d03824da52136ab2b3428e911538faa8d7e4c04	\\x00800003bce94e0d5955adba1453e2d1764350711eabdc2a77023005395abe9739b06c70425e54fd290c4465fa88ee871449030fb4e289c0a04b4269f92776c7176295242a92745694a0a8951dd2282e99fa81597e962f3da35844e9194c8793d7e13ab0cf77610332bdeea27e849156cd5d6dcd33e0cec09cf21573677f808a33bb533b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbb70217aed32c211ff5447c7a2b02378b0c4d1aedc85b3dbc61380cb00c354a900232a95633230c01b8bec43ddf483e3f15fe440ac0248237b6dd7fbd2c2c705	1639371212000000	1639976012000000	1703048012000000	1797656012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	79
\\xbe2c16eddcae55f54772cca3a133aa303828d40fa7e4fddb2951004cc102a0cee8aef6152bfb8a15b5b64038fdeee92f14c264a2f755da8ff474facdd1d89906	\\x00800003bdadf6cb30d8af14fe7b92677e7976d5a4398d5416778fe9bf076fb6e2bd6e4b406672fec160c488e74a7bb410d7a550ecb8ad0e44521f9f9dfb5598bce38bf405b5c266cd826d16160215d4ed2484f307f0eeaa3bbc40fe99def88225f4d75877fe53e93613bed3e39832bf6d8e5157d4c243bd33aed79b50a9ff1dc61f9c67010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xac6cecda7321a7fd030a8898ed92522ef1ed6cc9a9ae9ba5d2051efb8acaa056e238269d438dece72df010deb8d48051bbe6cf9c790c826e4daf5af017024b0c	1635139712000000	1635744512000000	1698816512000000	1793424512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	80
\\xcafc45c9a811966e36dc4db0e903baa7403fa53d07b8aee6f371e89f8a129628db2da6b12de5c7335331e9fe524472c0329900c1390e20be694b86c35b77c10e	\\x00800003d5b7688c27e8f91e7479e86cf130fb5de8accbea8e607ac7292051745be9fa0d4dd278e916671af09121b62ed097f2271bd9e38d54a83921dd21468a334e5dab243dc32daeb26405c20fa0703843d78949b9cdbd2e22e6b601dd2590ae504197c7d4e674fae12d8f98cbfe93b00de7db456f8d20324af6f07fe3f2930d2cad7d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x61a2ddb1f190e1bfc71fb811963665e4fe83608bacdb85d6bba3f1ee020ecca4349e63136a6a4fa4ca1a0ae265a5545b278a3527bf0285e0e80fd800a954d200	1633930712000000	1634535512000000	1697607512000000	1792215512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	81
\\xcf54fd8d605f99db424b47d4603e103def6b2b02b3dc69ce0bedf184203958faec2d91db10279bbe83223ad5ec32847c1746d9a66d91c05739872954728bed65	\\x00800003cc0c018ce392e8374779440495513b96816ca0b9ddaa5f62ae2752aa913a5114eea1b72d09adcdd33d6892b40f6ecdac2ed8d7b2781ef77d2bd0e4e804d18801405dc7da1f22a28fb28fd85d5d5d136164809c59ce4cad730a170013c865c27d42a1ddbbdeb32f23289432401f4fd25f00715ac7d692d4ca0892c3fc5ab4e69f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x05d3f88df5c70911be5e1e06063c531f811f68d9a317950e33868bada68e4bd67a0e15d4bf6671740d7ec9a9146720013c3dcf55eda24b699ed5a602b7b8520d	1640580212000000	1641185012000000	1704257012000000	1798865012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	82
\\xd41020c46e0ccd96f4d6d810c0e3d74ba55ae7c5a29677c8eaed7815e89a55c1aea2e8c009ec4385d951a3f29a75c4d63b3804461d0d9efe647adc9d1dc77d6d	\\x00800003b7fac676709c6b1d79ec1a30f58b59bc82c4c6ad738f9defd86959a9c0f38affe189b9a4f32ecb05139abfdad8982f6529aeee67e7f46cb807cbc53b0a1812fbef2143f2b377f0d146ff90ba2242bb8e5129e304d35a58ae40493bf25ea760e92c29bd4f994a78c376f4038cbee8066d6be8ce48a7afce5b841ac774876226c1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1b58345b41c22fa4f0d2017aa67e7ffede51e63b082c9da4813621de37de849da8edddec93c2f3e1d3e5f24255542c3acaf4d4998a1a096d84ab648a4e169108	1625467712000000	1626072512000000	1689144512000000	1783752512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	83
\\xd494c23cb8fb0509445adcbca2f678e8bd7fcc7a40256c2bc3f6cb8c6ff8e4375ab6055aaa8dd038e4140906068e37ed1a0c8c3935c014504d1783dac14ca843	\\x00800003cd91932da413dc979e8e1c83d73fc2db252f7f1d437004ee94310bb7a620c8f55f04c5f1d3c2b12b335f043776fb65e00dd16d597be2fd67403a3baa905181464aa837b65396fa32a832b7bc583c9b4b0aa678cfb439ac2ada21920e9bbc87013b2668d41f369ed1fafb4a711595aadf5dd0e9ea55911542dc8b3e9b06c30559010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x0bab8c58f4e3426a339ef2a84440da76a90894118a03d7f5fcd09ffdc87e7e2d7d09f0a34bbd2424dc0f479dea074568d82ccf05972cbfa72861fd3f39a3f80e	1617004712000000	1617609512000000	1680681512000000	1775289512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	84
\\xd5d0408c274aee407241818aee5dc02c51ac6522a1032d3ed315a731ac3547e4955703ab0d3dcaaeea252656250b612430816da40a69517b44dfe3de14d858ab	\\x00800003b3f6fb532c63376b2eb7769d66592e5db54fab4ba690391efea473cd7107cf9bbf1eeed2b21dd03db29b73ea0c9589181b947ffd30383a1f8e7e06103eb07aa3ddaf94ba7788597ad9f40f6fd39637e11fdf71157a735ee2b37b6b06cb668c1817cf5429e65775ae3918ba4ca62e6abe173711609473cbd51e3ded138d1f8bb7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9ff4114553f2f0f8e366d787731fa96cbd2c0d8869b283caf04c7f72e972fa30436cc58b67dca041f855c718bce614b2ba02317e3aab4a84e6cfb9519494e509	1610355212000000	1610960012000000	1674032012000000	1768640012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	85
\\xdccc42eabaa101b535cec932f7a0efbc1a195d2233f4a811f9ae7fe334dda117047faab8a422ca554f291ae73da2677b1704951a077740e6a031b7526793048c	\\x00800003c608677e6070c4aa725bd04ea86d096f12758228ed317a1159f6b0fd81a85e5f3d71f3b27ee68a5d66645fd463d0094c9a50473410e9019e391bfb0bc3f9dd62b658aa9a836ea377aef439379ad5ff8b4a1f531a515917d39c271737b53d2c7d7c87cd940fe32e6edf807179c361dee674c7664e602bbc41de990a6f9c46182f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x406af70f6714873f51c2782d941632bfc4611f1946c362d2cc7329f53b6aeca86d2c3ae4971433ba875b6e02aa4508e0b86469d4e585f88981478a6dad0d1706	1613982212000000	1614587012000000	1677659012000000	1772267012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	86
\\xdd44ec85e451f844ebe2bb420b4850843484575ef1a24ef322acf64d657c7d4a804d41d151eb8c3a0313a7cd6feff3cf02e690b9a1d39755ab193a5a9b6641f3	\\x00800003a88ecdcf842f464c02ea217dfb24c24497b8cf69eee113c830c27532838d4e7f49d67ad4793cb2c118a9bd89d6b0fee206b4db32e2127170ea2b8c855d0894216da055d40c6991dfa8dd82d6835382ad972ee33f2de7e89901885540a80482758e14a826164052bafbb9f238a9cb348c0926106fd0135c5207f5f57533811a2f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2200ecc3d43679cd7ab09e113205cd32540eb8758f9328ba938460c498f2eccf7b2387b042ce099858d900633a59d65f0548d0b136a29422c56fa1e78262e008	1610959712000000	1611564512000000	1674636512000000	1769244512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	87
\\xe574c059a8953b151e873b69a3c63a6973aa5bcd97cf0704d9eb3e5655fc0d73c45fd47fc4defbe8c5226ba66e7f342b397b4a39bbae651c4d9f0cc9164d854f	\\x00800003bf227034fa5dc0e9ff2ac75d285939d03a17055bbfa4d752fbd1201ece0d90b1af1756ae313bfcefa4680d0450c3b4360525b5f8b27f66c90f0a3ca17329a665d78fac906e703335c5c2ba5d81195784d7156885ade32d3db9d50ee9bca9317355d42fcf620a2bba40dbc7cf769bd3a8464a1563820006c9bb580c518d10ff8f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x315b92a8af7db6a56c4144c515d82f6eab1026aa0fec3870fbd6d0e71afc4c292487beb70419efbfe86935e0745bcab5e3a798e40f97840142599b5a44170005	1638766712000000	1639371512000000	1702443512000000	1797051512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	88
\\xe6d05561031d542a47237abc7e3cd0c0f85f07626cbe4fab8c6c05d8a269a72d97ee1975beb2e7d71bae04fa7c9a40f777ad991bf71efc3be2d44d504db80339	\\x00800003d09c196824f20e3c581cb8c8fa2a0fb2c418b9839aadf8e9e3dbed01d55252294bab37b2c71d07c2df68795e33297b026a0573d6494f155e3137133da1e84d5c11a001ce39644582b9d9f5ff956d4dc029a567938eb7ca585b69150ae05f05dcb812b4c03a40a3a7bc761b8eb02cf807eb7000e4b9ea55a3579cb733cbcca0f5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xeacccf2006f841c0ca642c3ecefaacc305391c30f278e773b738e49439dd89dc8f326f8c299f24603b571df9dd9e5cad27fbfba3381b76b414d7117aeb4d6d02	1624863212000000	1625468012000000	1688540012000000	1783148012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	89
\\xe77c71df64d4922decd4252ae2af4a427a6fec6787ec8d9c42e8b60660190fbb802a8ecb3b91f5b705a853e70f51f4d7df37305cc96344aa358a028cd4767d47	\\x00800003ef4988ebbb3c7173750a6f25bf8cb623948f1063d62bf962069bf4e65a2d5b9081b26663666f93a07e5b80aa8a88b516d904788c61f5ce0d406e2247c95b82118e490c9d1f7ce8491be9e4d5a3100e50e4b7bebbde85df8933a9f3138b8fd325539ac8628ee0c420e10b942bdf5d2b457c67f838750a50102bf5eda072bbccc3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x35054031c4c0927368a15bb523f5758f13fda3db688c84008afe588711274414e9de838dfc3c7e1cb3cccf4a9789c32f1f90004255f54586ff5dee28ed5ebb02	1624258712000000	1624863512000000	1687935512000000	1782543512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	90
\\xe88c4feb922fabd612716d98e0d986739ec701f86cf0f9d9aeee0e27041a66055cbdf251ca7bbd802131cb412103a2cb8483bae32b6eb2d7baf79beb17785c09	\\x00800003cb968896e4f0c0c8efcf010b29776540cfeea0373508c9b88a63d71806076bf09fa7c50c825e45d96d0bc21cf3a9f83355fd4958b4fd054e6d4e62afe25b9354faa95a041743aa72e695850e10c7a9f2b64cc10a0cd6558c65d2f06c3a6f9ea9df022d4c4e54d16bc565b25925cc8cc9d071a757e7a2d3f5041b761df6819e19010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x97b4b1598630bc5478d2a88b9f0d59113423839c054729c63e3d0eda261a3e9099294fe598f9d0ed06aa875030ff2938833599b0ab896f86dc7f14a01517760e	1620631712000000	1621236512000000	1684308512000000	1778916512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	91
\\xec748d59035ddc8da5023c843215da8753ada15703974f25f953c84272fceeea4de0b7b02a46e7f57288d117ad5825d975061c80911df7baaaaa595c9e4822f0	\\x00800003adcf84ef272c2bfd1cb92be3d1549c6863a928ac9f0195bdce7728765b802ba65eb234bf75117e32967b70afa0294cf455a1c977b6775adc7f5ea30ff727f4f8b6bceb9a2f0c298befa5851ec6ae53b5e59a9744901ac770c408bfe3c9f3a73625c18e5df5b06d8eacfbb3eb801d76bd282435c027e2a4755070eaf57cec0d43010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3876d5c3e68d8f4d8f204aa6784d49bb0c9464461daa982c0ea5e31c18f7db8d01e7777d508e451bb62421c4db2d07e2dd5d49d8a52defd1733cf4b3b4bfd20c	1623049712000000	1623654512000000	1686726512000000	1781334512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xed68acbf9c6880cc8402df700af8fb7168966f6192fb20023bf85ee285788ea8da99dcf96f1d8e632660e3d1f1dbae0af288bdc713912fed7b45468a82bbc298	\\x00800003b19d98e4fcb6bbbc4e15a0dac4d95a3e5136856254108749b5449c989b4da74d6ebaff5a794119ea4a5d38d5c18f1bbe9eff535c915fe167de5c87ac3b6b9932566f384bc5568201c59db14fe2552be9a9fdf948750e5229d00b01ee7f472af69ab6d75a0423ee479a19f753251a61e6d21d076535cc81dd727036ba0bacf523010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe1bf78f85bb4f579fe39bf492e797e20b8f90851b0916970041239655a726bc2fd82470f38373dbffe23edb3e37c48cddcbca7292227e318b0ac39ae920a450f	1621840712000000	1622445512000000	1685517512000000	1780125512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	93
\\xefa4f804adf19a9a7554def96f37190086936f9a6f8d1f7163641b1c862d1cac28309ddfd50fe7b503da649532719370bb42ef4c025bd50da8c38ef9d5a4982d	\\x008000039dace54689330945823f935f6963d628754942747f8f69166b654c619a015db9d5e25c7fc766f8024fb394cde430c46dc864e1a1727f721750a168bef8fb4b51ca72c3c6c87b45ad24d968d5f62e25e5bc8e04adc13da205d3d950189a72a197a027f979fc94508e432b549ac8b5d324539fb3c87f9a421b8dfce8d29863f6e1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x53f69fbc7407def16d0ac50a712d97eafb564ef7604d46f92ce77ca1ab01c11a93cc3963cab361f22a86f04cd99fb5416843a175adf0e58432f08fcc79369308	1634535212000000	1635140012000000	1698212012000000	1792820012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	94
\\xf05c7a72be06d143e9a61f99db98488079d1533c070bb326ee0b0c8f3a93d6a5a5bee23807759641f500cdd5fd89b911a03be12908cc02c05ba2af3fcfb8c2ed	\\x00800003c330ff3cbdc03af890b8071bdfd0d579d98100ae9c47b17a7c45c5f18ac0ede4c7ccce050a5f3e3ba305300ea99ef9f8f968779aa097bdd1f6774618a903df61188d9be56a76d3eb0047e25c76568ad17446a327708e21874a1c32b5ae5cdca496af7929549e5f4d9823bb5da1992f5210e213a9b2a0c923555de32f00330cfd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x088dbfb5191e4abb194bff4919a2e93433853e24edd9990ce97a1012642b6434d75e5e1ca5e67a734bb8169421c3b7c8778c68b0048b2259ec2da3a02d209f01	1626676712000000	1627281512000000	1690353512000000	1784961512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	95
\\xf65086a5c9ccd95547b9b632441bcb7260778c598cb9b1b7ae27ec0a1780dd8cfd81b0338fe3611b6e256e3e947a9db4665bb6aaebcf1f8007cf6e81cc56631b	\\x00800003c847d5b786b7a93503a38ce3d7cdadb10b52e5353bbc9b2ac3a7d9c714d0affcc24da8e278323fc920013b9f29438ac063906c0a4c8139b33c588795f3c1054f40e8da404c4bc05d2842ce3a1845082b908300d9988fdf4c29f1c5e253eb18178a7888c6d7802f084ba058c83f4668bae40af1bba23769d1bd385a5fe464889d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7c40e8dd5e0576a8bacae9819c25c53721d732f047f7c82258e8a9440540baf2bb95f5ade669a304c3889021c86dd5f826dcaf45909e8530dc66f71a923b1003	1632721712000000	1633326512000000	1696398512000000	1791006512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	96
\\xf82ce86192b3bfe730fec7015405c9a861f2509133d913986aa8bef038eed6abf4f31892585a3042536311b26e5d6e94f9e0542dd41e27391369ab97a6dc9a09	\\x00800003d296ff535a9b794332c683504de69308fdc3b784639cd4953f33ade332cc22c7eedf80b40bb4ca467b6b155b8dc1c5ea95fac383cdfbbc0ee38c00abf47a334769fd2e80eb517b6535343d2641a65d7ba447faff89e18148fd42201fcf71d668d5249224722e133334a04910bf1d786851a8067668a7df86c745d274ddc8f3b7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x863039ce34476f8904c6660e81ef06846fa633a2a8d80c0ed708a15683cd697b83cafc29c5203e6be564a908aade3ffa9c7188db17872349de0d1c72ff418d03	1627281212000000	1627886012000000	1690958012000000	1785566012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	97
\\xfd083580f55429dec9382eded6f4c24fc776297e2f64b709cf38ea5504ddff3b4f0e8171e9f6a13a9f3a29f192a862e4ed59c566a31aa530e932208b53d5026f	\\x00800003b4acba5bed9af7eea1fe2738bf7b659709585931e746ebdb7fd9e14f6c0e848bc192977cf0e152fe042c06a6fa01ac77c36045bf4c48c089724f946313f7aa5760ea8cce64874988c01a8a2d6df356af48b5cc0f48e281fb9aed53ce101c7f6d582524091c87aba9b23b75b5b29aa3a42ce7aab2b93f7cb1dd5a817252326499010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x60e77bae1ce197086b117deda23bead51780cead06dd998a8779c16385c997c265c89c16ece88f60f0b74b98b1912ce7eae4bcdee309cdcb6cc3f13cb976560d	1620631712000000	1621236512000000	1684308512000000	1778916512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	98
\\xfe94b05f6c2912219e5a5ef43aff159edb42402e468fbf7ab4a1db3c124a59d7a1db8465a6ae8a01e2bfbfb2cbc81f81bca9cd773f444e76b6936cda0f2eaa6e	\\x00800003b532233486164618569cc903e7a73c4009d67df5e339469425c47240f0ff39dfe755b3efd032e64ce0693284ec0c437f6860a1add7c868dd0c29cb2c90bfea742c800d2babe4b0842466dc8ff1d6804877bd451a01c88d047e4e7091e1995ab5b1b75f541835497d0db68c079a0ad16f2aa53a5d29f354485fa83a78458cbae9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x15d13e415c31746a770f52709d47e4e3253e94b2150096f761b17be08adffd355cb8f962725ae458049fb6bc45265adec48bdc5913e673f3af4799a526e16607	1640580212000000	1641185012000000	1704257012000000	1798865012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	99
\\x00b5ca6af5c9ed32f363cfab37cb82c21cf6e71634c120729f73398ab5099b5bdfbc6d723da508f261890116c03592378c9fcfe0a8a199069e2a68c2ad9818e8	\\x00800003a6de2cfba180b787d68323c77a7ccfa12468759caefe55567aea3bf7f189d1f0fdd7a064d0aef39778cf7c609ceb8f04df462a66237da9ef806433d5439d2f0764c45f308a7f56316293e8e1ee459ecbf5b772ef3bf17af8fdaaac8747c3a27bd63a9841ab1666b001c6a84fc750b5333b7f2376e962ecbe97b15cad5db8d3f5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa922ae9c78a8a9ed6f5d522c9c06f4722707d94d76eff23b98f4c1382ad8917c772b500438b6c81543bd83a31aaaba03f348fe9bcc3b174728ae9188cb29c30d	1619422712000000	1620027512000000	1683099512000000	1777707512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	100
\\x02f922aebad8ecdcccbbd1e40e2c3b88535ca88ec5a5d084bf9e0e30468427d28834063c9dd88a974db97c5839fe277e2041ce36e9bbf94520e68f65872d2dc3	\\x00800003b807051c3da1c1eaaf1b24ca64addf49905610c2660453b84871c2f8ba65bc81eb31d3a4dc73b5ceef6ae0b05b52602b83aa350f313a46218cce22a076deed671d10378280e4ff5b65dffefac44730a900ad7cc17338e9415214af55ea201546a36aab13e7159b31ecb51a6f6148d7876a3b787fce4fef95b836eba3dfb5efd7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x86a79a8ca7ef8a4bd61f9c7dfed0e1ef50d43a49c169ab06292e47dfe1fa634bf8905064fd77d5933c40f67bce6c68adf93a288b0a4e681675c8231201018304	1620631712000000	1621236512000000	1684308512000000	1778916512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	101
\\x04fd251620c8f6f238eb2eb38a3377326be3ffdb2e6d0a831e475bfb641164fa261b0fa2bd2fd9387aa303db59dd44e4b8ed89c3a19c5f5074b87bcd522981dd	\\x00800003acf93b818b087241486671aa3972c6dcc05ecf6b9095bb3e7e76b404753e396b30754b5d27c02261c2f40873281e6074a8ff3c306624503ffc5124a0ecfdc5e60570a493c0123544edf263130622a2c5314eed5de5dc27683f0216ab520ad64a7d06c0a60d451d27dd7c182175150f5b741c8c718b0a9db5fb291492a2fa052b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x008c081d527926ad4637ec42a75b2de38418fd2071e39109e72e5d8c41d743dc5b6a90e0503a64c629198f2bea154f191247af37b9a35664e3aad30a99689b0e	1618818212000000	1619423012000000	1682495012000000	1777103012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	102
\\x0809f4ac760263414574357fab56fff0927d2b6ed722340669c9e4c2eba52481b336aced83b2d8892b6e20951f129201f2aca6134c922ad0774fe9997102c780	\\x00800003cc6137c94f620a9963b4291c78917e4f55228753e84c47833648062f8695dd40d85a6a150165191f221af46a29eac1350be1b5ab5b4f81d24d04734eed62fd77d1da7e8ac239064da564da7817a85dde0a57bfc32c16b96f57b4d3ac01ae21c98b17c77b5c19a5b3b9be573b420a34542cbdb8ce40913c3d3ca1122aa0a3d66b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x790f7d78e2086be3c8913897a5d852d6415313de5e05cb346127502e12e580e23c1efb893149622fc9c1e92ed985399c3832df57a8b4161a8f46abb801d0f70c	1641184712000000	1641789512000000	1704861512000000	1799469512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	103
\\x0af5c38e90acb8e12c83b62b3b629ab9d1fa5b96bcd40c58446eb7aa6d494fc2642de0b54ce77577b5dcd3f50156748c029d2041bd2f8da707e8e0f43bc52008	\\x00800003c0c66cb1821e6377dfdfff84cee480e1fd03704a2baf0e5fb67584a7982f14755cfbdec7d5557734ee0e414bdb2893dc6e79e65dc72f81a548469dfe4ce911fcb61f67e8cc32a2592a7241bb953760c6fe8ba190cf2958817046c8c2be020a50350529f2f0f5ddb7274315b0910035ef0ffb85ab05745820d4b48ad7fcf5e751010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa934c371ac5ba609827210c2daf48f8e6aa99c7a30c5301af765fe42fafa41a31e21b812697dc0da59f26f73d0470c8e9dc2f0f64b40a06e7cde3e91d65ece04	1629699212000000	1630304012000000	1693376012000000	1787984012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	104
\\x10153f707c909ff2fbdf9a83b5ead45db681f4f5ee3a1b753a9778a0c59d8ea4b7fb3f54de647f4405bc49ac8bf6c01c1488c9f3cf9cde2bdc5ae4dbce0d17d3	\\x00800003da783c93cc37385e42bfa98102becd4bf71aa7a4f1bbf0b6191fe8d380cd4352eb3a82503113728cd36a3bcee819541121c8e0d76b6e450b73be0b30de573e4d93a94ed2cd3cea3afbdac5e556c716d173f6ac17c97bcbf24a6247346f5bff9badbdc423d89af6c92c0f09e355667247dd6e5e932e82e6c6e9cb8e7470fd53b5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd3cc03f7b2dcf233fb73eb69f7150c909296ebdb28f1b0aaeb2b9b8f56c683d9568d9904f7307756dd04014cfb7fe2134fb11da8284ed060201a74ba4a060804	1620631712000000	1621236512000000	1684308512000000	1778916512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	105
\\x13fd1c1e27badb11e10c4c94ca00462c1f737d97606b232aa5f8114b558e58689958cf51eef10028480f2ab871314fc154c8f4d2bdadab5b2828eb5f931e76ba	\\x00800003b7bcb7b40af5d75c249df6052137cf85e868c7a2ee04660f3cd10e9e0629bcb6b8972ed511f6a61a5f7b1670ac752bae8c7f1e21b44a327ec0c92760c669df30e4cba3140a380ff542beb3a449e5b384a7a6a3d92cbee7910074a4099585125a9b3c3ee850ad393e5226a66587e755b3f0af8bef7536e38c542e774478ef9117010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x131cc3c54faea04e6b6ab913a89f2c081d28643cc22cab7663cd221ae2f92615c9805285284edd3e5ca4f1b842ad498db1bdc0370b8f00e1f4c4ecefcf4f1b09	1621236212000000	1621841012000000	1684913012000000	1779521012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	106
\\x148978cc94a1e961dd0788ee7439362c29eeac4295d1875e8dff1451f529cfd92332ed3be7ca6eb8e48d1892dacc8d9a2fed80f52319d8dbf5fec25984dff5d0	\\x00800003b62c5b3e42e1c716283327d193b4e9320eeb7d3811f7987fe30decdb3bae862e40a8d33e1bde6a564105767035f8fcb50e9a9477c7cf0e096b6ed34413819cc71fa7969cc4a5c186d1c52a04442316165e5c9ee77b9c10271e9b4daac769b276140dccce8de82103a95a798217df97637288dfe4af155a4680b9c6a9b3bc3485010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5430fd9da86af0242e560d8d9ecb2a5a17c485e1c2f53c172fe03b3b6c8af3405713c721be5e1aad806312a6bea32b355713753b7bfec6abc9166b3267e6710f	1637557712000000	1638162512000000	1701234512000000	1795842512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	107
\\x17e16924de7a9b977426c19e73c9b0cfdddf5b8b8c7d5b2970a13df4ad42351902a2aaa1a12e83ce4d4e9095c22247704636bd2e5cef10acd848398d18c9ddc4	\\x00800003b0029e91170fa3ea5201fe6ae68dbab928f9559b84d592ffd72959ee9bfef9d4aa1d2e0802be01c03ba95029823d2951f3fedcf6faf2a436544eb6e54c66c2cdd93f4d8bb18fa8d0b6d4b0492a020afc3ec744b85d6ff423a684afec9337abac2481447e60748e3d5269f4538d3ac7ea9ca4f355479ff316d8630e59aa77684f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9c5c30e4201ce5f96e8e1314881fd526e4d499cc84150ae1bb42aa281fa079499025c09b78b5fee04724b882e35411a24f202872918e8cb69ce6417c31b54d0b	1621840712000000	1622445512000000	1685517512000000	1780125512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	108
\\x18e1fb095798bfb915805999ae3377980109061782c5ff1ab44034d025927272d737a1f9a234b19b47de85659c952cfc868e540fe2c0b733c5d3ad85f4cdf47b	\\x00800003ca1413df61dd2138d26b150452b612ae6c61e5280724bed590de445ad172ceae63392159310bb137a5786afbce163b88ff71ea379cfb255655c788860defb9d6766010c8560d33eb9f6d5d9f763b373fc46f1787b6bc6f145fef4bda65b43fd6e18603d3a231cea73aec03ce0d15c83aba6c72645a10a18d17bcb871207cf7b7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9f7bbb525e5f273038648246390f6fae49c0ce1480287e7e1e60f02bde503230497de2c1ccaf433963011492ddfabe53055b0edcb8c205ede681253351e9b20a	1638162212000000	1638767012000000	1701839012000000	1796447012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	109
\\x19013564dc481c2bfcd60884b2c830ff14a451bd1c4efe96a25547dbaed69158c13bbd65f74a93367138d6263f22b8fcb27a59dda2e643a812523b7002578a70	\\x00800003aee1235700f2c6bf5fd4190f0b6630e6efb55ae7e551efd4cd3e8865f78fa605338b3f5085f088ceb23836e8145f202ec4907d3d078feea9bcc9fb693d1daf34c8dc7e56b8d16dcd4fcaef33f4c5690e33a86128792f9e4aa55f62cb5fc2bd79c7936985fe0c5e29795528353162faadff7038d4635b3e94961b1811ecbdac2b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x12addfd300a32a4ac7223464308de5750144181339663c2486b03e90772d632f365e8b6cddc4653b782c2eb2aa388021b5b51d29cd5d889a0cceba2e1edbc80f	1620027212000000	1620632012000000	1683704012000000	1778312012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	110
\\x1a6dfae1166bdb972d37ae3f1742aeafd5a4ea916a2feaca1cd9f77f0f8f870e506f9fc7220c4a668d2d73c75f8fd7bedc9f96348ec030684de65f8ceb10232f	\\x00800003ca95135cd5e3e548b965c87f423b04a02965ab4c5ce06c30aa522f2880121b55b64932a12418d24ea0cc020e52a1d8b90ad6276ba87fbc84a09c4218287576b36684eaac89bd69b0248dae096ea29657ef0e4f9564c2ebce52850be77e3be1df246cfc6c919857c9023e5ce107f3cb52b3e269a8c200d0657e5f78bfb4caf899010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x12f1ab7777b7c01d4b09460f8691b9d2896d989f5c5fad504d12f63d692593863fc232688b0010792ef7a809ebd40796c68cc6fafe075323062fc68c963a4c08	1638766712000000	1639371512000000	1702443512000000	1797051512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	111
\\x2815e0fc261b1b31d56c3bbaf08886578f43bc9361f13e92bd0e1ffa7f886260c2bc3dee9fe874262f651bc30d764fffc7ca82a7ef1bf4eb35d82e6dab017f40	\\x00800003da4b92ecc768847b0cdb62e12dd966e26e55291439c400c08e1a1c04c3919db332ddaff1f8c79e698c651c940883faeab25ae25a8b25348a47594819000bd2af60bd5fa7b5ad3377c47eaf249f46ca3af1b6e9fb0468cc9ae5558ed234ffe9d3578d334b35ca3d782fdf3992c9e74d8330aab028636d2fee2f542b2a499c504d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7d4932486dc9f76fe2b05c1d4130d809129a66c780b65564e9c467690bf6c2439010d732c37c5cc0fde9ff44599fc04dfc53fb28d51763ca3723c4c18ccb7e03	1633326212000000	1633931012000000	1697003012000000	1791611012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	112
\\x29995df6200a5477e050cc497fc3ac8abf5127c477dfbebb58361108e27e703da3c43385cac255dd7ddac29b9c1aa72303db18f6107171d24486c6aa6ff5a678	\\x00800003cdca8fdb5b194720bbf28d9067b995a5b1efede9208647c0d924f1a39273b93072bacb8af309f2b539e83ad67efc1a1552512e1b9bb44a18fc4a19fdff88a25ba602b91c94d05fe11e2e5a58fd5d3fdec1bd00c86ee8f6a72aa6e307a2558efcaab6758f1c36669d2de2c5bc5d9d5ed5be9af6d9ae2a861529d69bfa9cfdd0b1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5c86d6aa8ee1f27b19c89ff45082867ba1e9995b7eabd59602f6548ad6f129da3fb3ed39d59d8de3e5c1d7fb2f6ef0af778311e8c15641549b5068b839d55503	1627885712000000	1628490512000000	1691562512000000	1786170512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	113
\\x2c6d18f8c512446953cac50544564709a18076517a8f2004f096b7ebf112908b0b73d481097d8bad075c7d754a1503eb8bc190ae314e4ed92745aaf8c84b3f5d	\\x00800003cc6d12913677ce113eace9f8951bc9190a75383e8697b23cfcfcc027f83e49d39c62eb65dbfd02b55e562771e071a9e1ec43f2e740d4a70b3455d67891e5848d2cdbe5901dfbfa4151a3c7fbd21798fef031e6bb0de425453cc396a34052498901c645fff8535205c36033fb120579b13d66477521be2923d6ff633c25a66f21010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x90d0153a58f9f0557e10a4568b825a319a246386089db4714a973138cd14052890d0dc65d92829cb4652d97ad0d97ebdb864fa59a3b4a3dda5f8144237857701	1618818212000000	1619423012000000	1682495012000000	1777103012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	114
\\x2d65ed5c8944205fd3af34e97714ccdf818606b445f62a53a6ce17381d1d6728142f1aa3ba5ab3ad074e37397d3a47df891f99d7ad479ab33581e59d58f04502	\\x0080000394e9ef1f160656f7c66a346ac38345b9d9d5404fe7bad791a80c871bdf70b04f111de6cd3f033c1e53c8d8eebca10cb978674ffa6020cee2f03ccbd26f43bd54a4aab331338b434e2c2d202fa3443545dbef32aac06e2a8371f879cd29a5d825e39aa64d8711e27ac7b5fa492d676b3dab0036413c784a80b59636b9a8517c57010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfec05f9c2433c0102853684064729c7781cf304d4edd64d27af6ecaed56716ba8544edd6f8ffec5f7e5f661408dd51f22dcb6209967af56360ee28feb77d8b02	1639975712000000	1640580512000000	1703652512000000	1798260512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	115
\\x2ded81e422205cba477e5910e3aecd731dce48c9c5cfc591081dd8af1b660216ee64c73562565cba4cda6693dda902d3d3fe4d6ad4c793921f6c9814ee37037d	\\x00800003d459ba1a928f9d03d9537a5411d31be632b6d1671be131523f01d64c8c0e149eaa59bb438810de4f7e1f84d78962d7b6522afc5f10bbc1e1d95a60b8a7ebd791de14661299862c666999541b4125443f6f5da34a0ceee0d8bf7d710b380433d362d0d0642bb4f6be797a4cbf68816cba7849a3c67775c4af1a91e01798ecadb9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5370b2810b1fd3dca8cf10b2536ef9c7d348bc57214f5f82c6d6c4ddf3c94e57f365e67f767d7323c623b04916b734426f804ca49e4f67b8ee830f3099e7240e	1635139712000000	1635744512000000	1698816512000000	1793424512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	116
\\x2e4923bdd0658f2dc7725bf1835950e90c846f3bb36bf6e19ca96fe8d20166f2be2570ede3b57d32eb6eb099645799c3391369873c3f86e5ccd5673e72527854	\\x00800003a9b4719e862a39101ce8aec597ee9c8d5bf5360860eb4f9f8b0cd977f5ae71ed4f19cd3ee787d0e6b32bc010f83526249224f01b46ff2eed2f6222f40c40338924d8dc1c31f5bce6f984b9e8b8fd328cfdb47cf28aa0908ecef9e93d7213ea3d01d113fdab33cbb517765741f054b8a051ccc246210638a99bdd8d35281e85e5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xca1bcbd8e9cbb0a46b3b64e2f69afd6cc763d5c39de29dbdced89df183b56dfc8c2a0841bc81a32057394a96cf9d32a790a63591e585cd6e41cf81efac7cc008	1617004712000000	1617609512000000	1680681512000000	1775289512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	117
\\x341961c21384c519cfb8446070c1e1c0293e32202ac21a561f42c5681dd38eab9b1f94e693864948152d5735b4ce9891dd83069ad81f3378b01ce8582eadf7a8	\\x00800003d7e5a515e83b618fb4c0b2060a76639edc628607b9f3b3c72d79238550cdb205ddcec1728de0849134fefecde9601c3110eeaab9eaf7b6961b674225ab488d398337bb1795daf74fc1ab283f23448220a126e985d9a06db2a1547dfa56fddf409fa676e855d5a4dbd12c05880db953199e1291ae1359837fb641780867cd3a29010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x84f1b6c12153d4d6db32e00ca04bfe608d76efda7aa01dff941644decf427446ef5fb78f5809d2ba55d8d8bb770334e8db15d8618660b306e486804b82a93f03	1624863212000000	1625468012000000	1688540012000000	1783148012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	118
\\x3599400528411524ebd707b8f51bd20a65dfc989065dadfa1bf57053e2bd9951c70284c55fc3304bae64e2808f76a621d10aca4510630108d21d3060d8ed008e	\\x00800003d0e754c15d6a925b71d3def5a2fc4eb9100535d129a32ecde73895206bfe46b36de87182ef2b86cdaabdb61e28fc3a91f46949561a55fafa935cbec4891e634438793347c5e84a1d8d8963716615acb1b0e938d032768ef9a1f61b401c7a15245983e9a19b5ac0ce493686c33afeccd5fcd43b9123944be325069df81586d1ed010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x174871f54036fded65011ff5738af05407a9ea18171068ed73cc61d3d11a4bcc1ceb8fdf792bbf17e6d6d1e7bd84a0c3ed5b9aa2379650e678c102a1d3b7a607	1621840712000000	1622445512000000	1685517512000000	1780125512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	119
\\x3531fef05d1c5d37e9ac88ea4413a2b230dfcdef8e58abaa1f43485081cb87c88f352b3b3d4f257f44d460d726b55e3d17772c4ee5b6a27c22bbccebee10b65f	\\x00800003b2e0426f53b8d27e22ce9a5bcf13a10f118c1cfd0f0673aa3e1396672e6b7dd679d2bbc29069ee801210ba11bb4d36f594331788b8838d5609a543e6353b829211d03f8fafd554137a97ea2729aa04ec8d732ffef34eba15be2750960dc7ecb11a596ca32d9b5aaa63959885ab3ad83f881ff96c9c7a6106a065b67478dc801f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfde89cfd63efe502a81b2ed5693b840df2a3abb1d574674df5d1bed1c96bbc1b368479e45f5c7e986f5c16213ca9930c391c3952ff8b48888641a1b7643e520b	1619422712000000	1620027512000000	1683099512000000	1777707512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	120
\\x38dd9bde42bef10173488bb4a3e36143d0253f559c239d59aae0f698724a33284a2106022d52453193c3913c6ce4cc0a2ed9d073f4b14d6ba2f0e7ada6e641b3	\\x00800003b5caa2bf6d09ec3c9255bce96e1ad482aba061141b5d003617006b553ddff40e93472c0852d46a50d75523166e50c7a66254b0b3504626695aa3c54a513bc011e3004553d590666b41cf3880ecf4bc57bb20f2322a46ae09b7a2ceb87371909efa343fc29651e0b023eb17613bed14079941797b37dbae65e7d04f494d565ca1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc76b477e24f6017a66c5926d525757950a60fc594fb7f698e97af6ebd38fe3cf83cd5c18861e9f032c045766c7fac0096c99fc9b7fa3f48953f3e0e529055b03	1623654212000000	1624259012000000	1687331012000000	1781939012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	121
\\x41a5f2bce8a77b58a4576f707886a28257d62c8f6be47c58cae234d7f74301e921a60a6613c332af02d0824764fafff5845bb40d4f8d9bd9cb9e1ac5d0e0a838	\\x00800003ab2d154f0b93f43fdd1642327fa24fa5ebb93adeec62bab9cc5839ba27c6268c88d1de537037fe24f6298fc310d62209d4f6945ad3c5f1cfd2c570509cd17b2fc0e182ee6d1e8ea7c307999e413cfe868679f6d95dd039f39c5e7365ccd7e7c4f011b1101c23a61675a9235718f169afedd65c7ab39558e78658f6fb23c05721010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf16624236282830ad5ffea0afa1f7455a516febd4db02eaa671dc198099fb6459f80dfeced345665553f46e81b37cdb4f715575f6518df5fe87f01dda01d7b0e	1636953212000000	1637558012000000	1700630012000000	1795238012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	122
\\x42cd81a8384f1f94bd7ecb2831361118c482ec66b35cd155de7e4d42cc12599df6f2592e9060880848dba257fc1244a440444792d8302cce9a50fc756861c05d	\\x008000039e092ae06c7194582cd772a2aebfa901ddb64af0ce9113d019ce8f35c4720d1fa5941b7868a7bc43b000632b1097bf5e3af6a1901fa91f51b2afa496b0a3609dcc53a6401a0d881c0e1b864065d9c5c1bc7f70e095f423bbd63ee0c96eabc57d5fcc881ad26c0ae4ccdebedd9857649ae5dd059bf9f26cc5fabce1549be6d16f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe8da41a316e99dde7184a8158e2677a4cc429b6181b68d157d6c8903d3454085a3b3cf10ab855161532704df53f3341d33334aec3125a6d8fc64599e1569c407	1629094712000000	1629699512000000	1692771512000000	1787379512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	123
\\x44cd3d7da36470cae73be2c83d8e0384b8f11a1b525a57c5c99abb355bb6171ad1eeb4fb2d1f97d155534fdf72d98aaf7b3c18db969be7c8011be32583371af3	\\x00800003e4239393eb005cb1ea30c2001961925588b8ccbf4e5359b38fa040e34b7780e30a6208572c0f1c245f10778352aa48cbb8966f93110896eac77dbf6e509fc46bbe34413d6ea20c4a08ccc6a35123ba9ee268b81f2285319de4547d0917cd273a5266df03ddd70dfb3409485e8b5d64ac511e3cc9257ae06f1d1ad99b9d9ea547010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4ff7c01a10afc59a3a0f7d0b7def400684796cbabd95c18b3f3eb8175184b543c0e8c11da8c9fcffc2eb7c64a4f70359e966cf0afb9602ba628be6aebf772f0b	1636348712000000	1636953512000000	1700025512000000	1794633512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	124
\\x4595e2dfb07bc5dff69d90c12c1643f32fd67f4c348ab935a173a776902bf43054141f093885e778b297b113a408971ed39c7f72794629a6175c5b516cc02e13	\\x00800003de2e0b7e7b06abb325791dc8609c863b1eee84fd75fffdae40e5b35678aecbca5ec4b3e4b20a36466933ce2777f490835df162e0a3fb55723b2f03c21a106b7cb7bb3dd937027761a7ae89735b750b6da5cc474df396bdbaf63770cbca18a91458feac77e0fae23d5dccc9b9f0fdb1caa312f3c5b8f2cf8e1199a98196951179010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x913ae55f2680a66cc6c4bfb2c9460f764f4875c9760aff8ad68bbb372e80a2e72a6870b3d579398efaa06d6bdef32605209d2a4d432a0b0519963afbc66f4f0d	1615795712000000	1616400512000000	1679472512000000	1774080512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	125
\\x49c965bfd224128c767a60b5a4d1f659569a482eba670e910ffeb96dd02dafa824aa3663430342d581cdb5efb862e44c1df0f9506db84a8e1f4d7c851700595e	\\x00800003c1cf3e91a7341a4782909c4da464442d14278365612919a1e4efe09246af0a94e996d670dc0f99f4a7c21ea77f71242ce8db0234553db3670ec00bb52bf9546f9f1146ae4ebe3c1bfed52adef534e5ff0cba7a86ad116b5e3c2acd7828f99dcf906eaf18369ce070e575bba7ac6f014f2592d54deab472e2229a9e5d46091bd9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe2ab0f11e6d4232217388aa3ef029e3566978e8c62de767e8c40f2eab24d52cee9f64e7fb2fad9a61b0617c25603c3f612d6177debad9a36cd9f2361ec49300e	1639975712000000	1640580512000000	1703652512000000	1798260512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	126
\\x4989a52db7195f0784127d38524e2e58d9c51ef3e19c8a659de4f62d5a6e654e40b782e68cbac6a8c06e549b273985166b538ccad29083d3e975dba3a977a3f1	\\x00800003c59ce387e8ac8de485db4f86648708ec5835dfaf01af840fdec78089beed29e4b5639cb9dcbc4313b1cf1b75eec1dab171ef6cc29234d8b88dbdd6111b170e3cdb0aa5322815df69e2f8e5e8aa4e83474773868410acaafe83a4ec38f9ffc413ae0f6beac3d68ac7bcf05429b406e3974ad5f337a77af323082595bcb4cf1af9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7ec1ba21594b0ef34c5f022e871323ae2cd10c0abe325b3b875225053767a85c6f3080061c815eba9447e051ef35d3d4a61d3f3eed4f98b6c3aed71b13a29101	1625467712000000	1626072512000000	1689144512000000	1783752512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	127
\\x492d579029c559a7dbe7f8e98ee314b99d1db5a6bbe91a95e5d23177186b4d6e91d1decdb67dd7411ba2878a99fbf2562c930e1492530bee265f8087cbd344a4	\\x00800003ad586b242f0bcdbfef30ea3b83be9821741db3566a846a7e2b578e6c389bf98c55d63098f7a17ae74bfc105b73e098cda55f554cf52ad8cf0af196b5a3e635af91bcfbe12159ac5f97434983d43066ed6d170b9e98d1cfdcf4931d144883575742b9b80a518022189344065d144c870ad4094fc427759576610ba40b8154e67b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x044d44840967bd616bf5cf903af7c827e57da11c71b1f44a1a655a69525bf6ce96010320024f54becb5504dceb6a75cf86980cc786a9319235fc32e29b083708	1641184712000000	1641789512000000	1704861512000000	1799469512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	128
\\x4f6df3f2531dc9f9412d08c851ad248fbaa253782e9e570d063be4d0be113a42e84e9a330b00dd18304d872799fa512d00eb0c9eb5fba647cfed1d02b57f7431	\\x00800003965781e70d7cd2a92f1f66cfbad1bbcb4f6f2f6b2956da31374659e531842ef0db0929b47532469459bd190184c37b497a85a11b88357418337d66a5e42c0ea0d5dcff31b3dc6941f141ca56b954ad949ab9859a4d045621c725ac83a10fe8c91450c0777d42de64bcf33dd471fb32ebef0e5c446370978a3f3722e5a1b62945010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdeb742083207ee7676abb1261fb379d23d8c3283b7d147835817d92ee51189c9998c422c46722d88081ec0ebb5febe19ed5616a84d5adf6b702b414dcb917303	1638162212000000	1638767012000000	1701839012000000	1796447012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	129
\\x55c53e4a342204edc62adefb8c24bb5d382ceea09e509b5a42af9ca212f98834dd0391b488f7e781c8fad12ee692b29c601df493a9f4148d941b85a1045b4df7	\\x00800003a0e1fbd0fe9951c66b67af6ccf82fa5141a20f126743af150613953a114310c160b1dfc4d088ef9ec87e8d5803433b1fb36bd4ea02eed7e555f8186008e9395f419bf14005d44cbb65fd19c847b0169c77ed73999a4ed1504b71be6b73a8833abe6bc2b9463911b316023463556cc5bb399755466c1501aa4a384a74ba0a1313010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa522e64bcba360f4eb3790d1b7656c77f5dc0c3dd1dd29c33dd7f143350342460be0dc7fe42f8023f13f488679bd35cabcaba17948b8aaeefdbea5f93dfbdc03	1630908212000000	1631513012000000	1694585012000000	1789193012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	130
\\x5631a59a407fd89e4303ea0edd1dba75e4b5e89cc282c2683008d735f6a52c05edc60cde8b2b3143bebc4ab990a5011e86ab79702a2d3187343509dbe303e279	\\x00800003a8af274bf1a529b601a0558ba60fc63f9785a9016750a56044035efd88d4092f73864427290132e9f26ab8fa62a367eef85ee6d87e4da5536edaef4c40c547687c99cdda128f2c64c08270697cfbd37550e81cd6a75ebbfa3618a7843d0e6da6f56263fcbb70eb3ed8a752b1f42ffbb3e07e29fe2eb8eed0dfcfa9d6c9e4f0e7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x51ad3a5368fef038f8b22650c8c642e7405af401e120b4de9478101b82ca0a915178b07f92e052a7988d71e7e176fce3e4e97dc1ad92908f9b95d8d8a410750d	1615191212000000	1615796012000000	1678868012000000	1773476012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	131
\\x57cdd28a5c52bb0d3a0a72f7a8bd29eae22a7e92b7e7b7d12431305e6413d9b6d2bb3d84b8af815e5e37dc06f1f812a2f61122f8e8fb334cd3882c2f764e8bd8	\\x00800003f084cdbed1b4754563e1c1226db28ad716afa7391de03a7098a42915955e5e35231d8365d1a262045c83090ead0d1eb904433d38c7303ba4a5b67bbb0a12abd745458cc1abd3ba227ba82f592f0492387160acb31d0b2372facd8756c9bfbe2a03141727060b9cace47d6db079536ad7ff26ca32e9b12135a46aa861cf8af701010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1b3ad766bc5d913cf0140bddf4510e0042611efb695b3ac8cb19b75c6e576b4f918571c777577a10cf03ed0cb0a52ee08d72cb3b531b842e0e5978e204d6c005	1623049712000000	1623654512000000	1686726512000000	1781334512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	132
\\x59fd0ec2d40b0f0affba21840e5a4cae88325370715e926ebeab9fc49db9c74603a218514b7685ef717bf320302aaa1bf032abf080378b243f68c7439efd865d	\\x00800003a15806ed5d1e989aadb5a8b986f40accf4e1c2d5e06bc718e6ea88f967a5b023a10c76b65f4612d2a40840d1056900c9296e22d17a951cbab53a7de52e2185fb4ce4f4acd3c6acfc4c61b2e741783b64476e7ab7acce781bd136365f8239168d763049b582190776a405399f7a938af3b81d2f3b40b1c9438406a7dbd3b6d117010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcee2d12b7673bc5fb8156f5f598d1fa5075f7a86475b4554be78f7092979a068be874ae212b160f011b5b4c56adde6f6879f2adc83b4d2f3b7b0a08655524e0c	1636348712000000	1636953512000000	1700025512000000	1794633512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	133
\\x59ddde4bae6f397156932cf80d088955f1c534397f749904bced2ada37d776750f584c0ada1ef51cf0eadf8bf09bf89212978da40a7d261202ff40e4af81ddcb	\\x00800003cd36327e6e6393f5e5b5638f6d32cab48129a0fbaee27c4a9016640b445855def061e7a3d3560261bf2b074d580c1bfe622fece1fd5616a83d4c5fc7a9f865cee661db6a879aa9326b182370e2deb6fa6487b7523df49ecd8a67a0afcfc4d88ad2a42d1d2540617263f69b686b616023483aaf9731b93851ac9c1c11b4549313010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x114b8a6ea21244a617601afdb576dce250a00cd26628df122771bc409bbb359133a64f2dd2811075b185da19b158cbf5545493df92894e641af99c939c19c70e	1636348712000000	1636953512000000	1700025512000000	1794633512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	134
\\x59c53ecf24b01460eb84dff2142f2b118c6be96a2c49e875eacee5b44bbfe65431f5069d6bb39e5e5497e6b61b285bc599a2ffc40bcf52ed52a9acb4eac81d03	\\x00800003c0241c1ae7c4d3aaffa25f3c5aaa48d3c01d13254c34cfca29789791e4dc7d46473a5604bd440e4e7aa19e5a67c957789495a51a2713f6c44c8ef14f412b77b9989ddb945d7e2f763bcb996c7a6beac4a64bcd77ba4b8bcff6ed7794856abff66aea689df5578e0b79b0970dcedc74b943fcf7b5632f9aa719ba8336931598b1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x587ac1e4e32a9a1c7067fcbe5310dfd97242521b73a8b2ef71a198d227994dffff416d8c5bb13b4b72b2af5b5afd573fc378f34b1d211f861a4de1f42d12800f	1613982212000000	1614587012000000	1677659012000000	1772267012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	135
\\x5ddd1f1e6b6a21e87ef8a0fb1aa1c0395ee8ae4c64a8d3c19636cb4469c5333103aecf0406be27b1b7901121da4914e8175f586ce6452aae2f098ea6f3840a48	\\x00800003dc36e907e0456cf208cf20928795d6ab56502568618702f7fdeeb339a591d2f7739e8dc426a4106c7e62356708f83e683a016ba66ef7bd7d2adcdff0c909fcb65e83e84d1a1310332fc330ac778326f118e224a1e7f9b3917a4c6d2cb9b52785482d574b885f67ef91c591cd2078f4c1f19719246d8825e8f25e7e624f486dfd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x46dd64342b7468e60f39792d781e6ccc5e13707450fb751dd89e3e08d8924d63dcbd9808fbe332819cae142c18eef2254f90b726adbd035be5d315f3aad50a0e	1610355212000000	1610960012000000	1674032012000000	1768640012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	136
\\x60d947c1d3ed6341dfab690adeb46bb03f12d028f10d3a8b10572e3ab95f57f891987c44de2c2b18c2fece852fd29125dddb368269aab2a3a30b6a25fd4904ff	\\x00800003b2cba12efa7119d77a09bf9b9f36717f144db1d82234941795fd779ade151c7b39773a72d4944266622236cfae6c0989c498b8a8062966947ec9ab34a8d941e94940ecd4fb0e0d865ffee3093871226b43088daf35cb77730a3080ceb6517bc696bf18110ea819b77a4b100b9a4aba8ac81c7da1a1a52ac006fc8b817f2c7039010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x017ae69622f74fa7bb709055637f3b10e7352519fe21f14f21cd804b0d522186b269528cc19f9b729ae0e07be0d0dcc37bb5f38f7a954fe2ddea5e1a4f9b990b	1613377712000000	1613982512000000	1677054512000000	1771662512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	137
\\x641194b19325c8a817a5d54782304c9728409da88e4f1fbbab33f9c64881f616f4d1fe799831cdb1e134a31eaba1d91ee65f2d44a100c4fc614a6dd650dd320c	\\x00800003c6e8de0337497b316329121fc8fd7c3a877c27c1a78351463c88e903220c90c2962f3db8b8c376e72815a9bb8d23ed1cbd45032a9a377eb5f398b7e7ede3d641e009b1e7680d6d1d15caef511b20b6f72a78e407aa4542b34d4c4fb2d9d799c92c64aad38d2996127b5b366a12ebe86217bd8d8b135c978d5795afa15b2cdad5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x09e3790edf5db4df9e425f7c769f9b5e306f0c3a2b1a52e132f295bcfb34f71a4fd14ff9a242724a6bfc49731ce0264e081243f2fa9d97b3730786466adc730f	1626072212000000	1626677012000000	1689749012000000	1784357012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	138
\\x6509beb325908094f32c971bf6a64d07503d22d1b8f321e0e0f29924cb52aa5d9a9177116e099116503afef005951eee69f1b203062edb63eabbcd08bdc8b761	\\x00800003c161e233db091c1058e495b913da9339eb19fafd1de7737e44de7aed4cdb19ce5a35550d7f0aefc94f833e1b7ab61a3b4960249d0afc68401496c1ae60db80bdbd5511e944ffe7a95d2a3dcdb7891d48d7c529847bb008cdf450f7d6ec7a7712b28e0cd3a41f466a836836a65ef6bfafdb4826955d2c6c22f8fab066a4e8c37b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x05a68d7a2b9729c2302a4b409e1464121a6061790b5f39506c7050f6650cf47fd3b6bbc732b27a2d1674d39ccfc76eb8212810d116969ef5de248124b57a9b05	1625467712000000	1626072512000000	1689144512000000	1783752512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	139
\\x650d34af03dd0e79a6bc1a702c96a354bf89a5d3c642a3eba5730dd713bc9df3e5edb49eddde26e425f10bda5c9629db1c5d4dc7708703b6b4f635e82bbcc7d0	\\x00800003c8f27e6d3cf31f06ee4784c1668e298b2684ada76ff674478287b0418832b08a93e2349599a0ae5f510f5013fd876f25735c1306ca577aa5cbc620ec16493e6a5694c44c6fc39ab7df8bf2358416c0f7f5a89eee7778c995541f9b29752cf77ca21ff00111f2f3f7ef5f945a1670bead5c2dd5e9b2c06f5880db5b35a6104ea7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x729b13b5585e34038e0a78035a614a40c4acaa3bda1961ac5b5868174610a39ffa79b3bc7810c78ef85059c7759c887167fcf7b752c1c4669306f731eaa72003	1641789212000000	1642394012000000	1705466012000000	1800074012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	140
\\x69c902f19386a89b270aafc9bbaa3680374445bd70aa317064525eec5a131ad397a76ecffc6cca632e1aee575198ce7add5e8cd24ccc7648e16eef86762e4cb5	\\x00800003bfc7ea108218c7478b1cb21bf00e40addf5b4c8731e037b5b21b494d8be60825a5bf16e5cc27d60ea859df5026bc4b0a9b34288fceef47b2e6686b5f5cd7dc78ccb50acd9725d56f4457756cabf5f401d9bf8e9d8b305fe0d83467c197f4bbe9af3ca312685cf598d3752276ccd4be14db9b0510f31d3f37c5c36355b0a1fd4b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x306306c610835ec4e33f143dfbd860687d97268e0a5d4df1d0d6165ad458a15757f79e6467a28f8eddd9925e3fd61844b74f516a736aed80a4e46ffe0cd75b06	1614586712000000	1615191512000000	1678263512000000	1772871512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	141
\\x6a0958640200c4b1835e3c695e04ccaac6c2de7998b89c88f94cc70ec3c203ad35e073fa8868231c24289221920445f4ffec6528278ce366aa24bdcbaf79551e	\\x008000039e9d2936cc4a2d361b120dbdc69f910b0561cc82a092cb408098ca44d8c5fabbff947322fe3b5817c6091317add4a46063f0ff74792d4e167deb2b25acd32475e21de6fe5840824d08a99b19bb56481f3e93944bb56ffccbb75a766478878e99231f7e7d060f9526099a7c9cd5a079eca6a440095233eb875efdcb4afca11eab010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbbcbb65e8912e5796b111f9a8df7dec974a6b0dda819ca273b221eae22ed828185dfeca2111b7cb63fd3c38ab1a6346fcea5c55d72bb8e71c8492ca8e83ebc02	1613377712000000	1613982512000000	1677054512000000	1771662512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	142
\\x6b1db64315de4e6f5418da44dd61ce889f9718017973f509c337d37bfc61efbd487acc78724fef909e7175660eda0a2089b22499650fee5d11cac1c31b239b76	\\x00800003e0b28d400f0cf73e5be26d86a2f681e102f6828b786d34eb946dc1f213ecb8bd4e3f4af67c233a29394e4ccb4d029bfa002643e6a0652dd0141f508204f6a348f9a02f1036a8895abd0fed93381182ec63df3b7f4efe8a52f959c74c2c37b8e28096716b328a25bd97ef4b90627b7ad24f2dceb6f2c5d8518704c1b2542eb0f1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1fef78a02a5c953c9dc72f014c54d0ab7bcea8fa1f3c613cbcde6417f8aca528e135c8b91a43a40d01b88c9fae5f39c7cf1f6e129389b743992d7eddcf91bf06	1638766712000000	1639371512000000	1702443512000000	1797051512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	143
\\x6b0541a5ef831e4aa3e5f3289795aa72d3d4e5f370cb33e4e2f7df2ba6436f6c122f25079b6d1ac4881b104facfc181de379718cd86fb1bf661ab0e48a2aefcf	\\x00800003bd617205be2fa4239f6e4165e9e45edbf9bdd6c46223b3ec6650bcc990c949a8d51f373f153861d81877fd3cbb1daa5f0478270e927769313b57c0c82f6ce0e063edce22a514f06ca77c28fd481a183101dd1868718df4ddb329e80a5015dcbe4cf16b91f2994563a52992926b2ff4fe97740ee827344b8d1ab350b6e26035ef010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb0daa2d68f3dfddfbb15e0c2930cd05619607fa7eee8dcefc8164f7fd32aace61d4ae28ac172ded14332d09cd16756840f878a44b0d9fd1502829c9014c32002	1629094712000000	1629699512000000	1692771512000000	1787379512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	144
\\x6c6d12a7b92d8f7df71dff910c96f23832c4d432e7e3c6e0595c1e758c22b37a805b5a73d464039bbea17f0ba9f45a7415eb6464139631e061bfe7239d8a0c04	\\x00800003df966cbd8e79d29ef377425579690dba8093b59ed20db8167c6f549abe95327426b10b0a73e464e7bc3509277494b7cea816dc14b40016a7f9fc477874e94fd741617a97b7a577c890c390a02395d7927775f1d70354af886bba5cfc27d7924d8485b8e4019d20df75732f1c1cf312bde91370cde10b8cb8ec6c1ae1893a0913010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1545952de82fe46f4577b97d1592316c0bd20f8365184c03f64f38059d23ac45e9e307fee42dee2bc1d87bfc4de657c5e6f2af19bfd44b903a378ffe61d6cd05	1617004712000000	1617609512000000	1680681512000000	1775289512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	145
\\x6fc9205e4f20462f59bdd3494883c2b23437474f56f3090ef949d9fd1b201f888dd220f1d233f44ec0c0ed472250bf4da70d0453cc7b558f7b0017eb7071b5fc	\\x00800003d8afecd94bce9c6bf47bb7450f109e93b1357f7ddf916a04e4852c42f7e85d6b26198144b69b47d9a531d6b01535c47a9fe1fa64662de0f5ad53bfc84f0886b56130aa46f407062c0add4ae37faee63bb3528c18c4f442cda601f60a77c761a64da9a224876060bcca54ce56698422edd3d8d3df1147f5f96ad9019ee5110d11010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6656336c96243816ea0637701a58a90b3bdb348440c8626a23ce33d693fd93c96ce4f3cee5751bc32c0a3ddcb1bf302b98c5dfed27f3c4199548d02f54959b01	1615795712000000	1616400512000000	1679472512000000	1774080512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	146
\\x6f89773115f85421efa1c0fbe39982bfbfef1acb8200ddc3eb3c5e960d9a63a80213d4d5cb4bfbc8f9e11be7b996813e7bf84a8a8a20e29c7ded01dd657b87e2	\\x00800003c92c1a74f8feffaca1b08af2ca4380d4d290cb899134303125bde1dc399f07b2879276462d11eb3ebaa1c5fb7d56490b1675374a8759a2cd6d17944c94660e44042b0ea95f8850d7cf72ab64ad8b65f489986335e302578fb48e58c26134261396979625cd8e90d5512e41ddd023aef2d689167fad9656275d2b8a1bf7763481010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4b86803f2cf98300b06212a86397bcee00028b7b8a6e3bbf5750f0e3fd1f4816a77fdc01bd53f5aa131f4789814c580adef6691e3feb5378067d979dd27c8d01	1618818212000000	1619423012000000	1682495012000000	1777103012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	147
\\x734d75fca782e119ad7eaa2aa2f7d0e6d6fb83bdad2d23cc2e6f7517b739da3409a2efb16e73c5025c56c59b1363242ffb0704dae9bc7d2ce4c7e10bdce76b5e	\\x00800003e489db59802ad7b5ebc7e5e651ce9b1bef2a77e34e9eeaf044d2c5ce82b7604250dc5285ce8e299258b700c113b3424690fcb55f3d6ecbadecf1de210a63b7cc99414f6038060411bd4936a760f76991eafdd2d8709c71960fb8271f99c28ca28ef1feec1f736f1c3e578d66dcb5912be4e4b12c7b57614d156273e9fd3a365d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x289f132b612cee0d5691a1e3792bebcf7fe9182ce329a322cd56ed9c0b007428b31378239b4d455565a0b47266b5e4ceb687044918aba37315ab87cf5e04bc0b	1635139712000000	1635744512000000	1698816512000000	1793424512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	148
\\x83cd9dde5493b21e84ab7cf27853fb3834ae3999af08f160ba74a0bb1e37762267795232362dcc11694903e8bafb83254b6e8db4553e2204690baf3add1d29fc	\\x00800003c0b9be92bd245bfa8a54ab252653cfb637926bdba85321dc82e6a2104c1fde1287d933b51985d34a3cf70259add2618e2c553ce3eb5853364c8fc04e4e717e2ae3750aedb901b307c83b879c8888804c59ebdc4d7c09667131bbd35906b71202b860135592035f1d9d899a507f1c55c22d2d621777bbb56fc775f1b07d2bf62d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9283540c50657c27e6b730fc4a68089fe66433ad3953ba020f5626683b0d8ece636ddcf1ef5fc4124c9de24e05d0e3cbf54744a153ca8ac6e7d7e0caca3e490f	1616400212000000	1617005012000000	1680077012000000	1774685012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x84714ace5e283f8483a44224020bb0c5b6ba8af9549b29df3ded1f5a65e5b3e8d2b1ffded94c5882f5af9d9a50443483601a857bcc26ae26c72abbba20b93941	\\x008000039e1c62ee409e9aa966124616ce2c715d4be87dc3ecb94d1ae45909090c8af7f2171887f4f8ea20319ac8df2c983730de72bebe4f10ea3b41235849d938e92126dda98c1585b0f13cd5c2e3c7b7e678e3b11a2050b4cee4651d762c6cc4fdcf2b6414e7d812a9e7374686ac8c21542a4bc2ae4272da9caffad3a5620c740b6f11010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x99d56faf95898e9a795de27a29fd5bf1bc522a4679f06015c53b037d6d1cd95801df6e82addd1d860d58ac1a9e301dfcff461aab81a8e76f60418cbabf1f9a0e	1621236212000000	1621841012000000	1684913012000000	1779521012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	150
\\x87b987d441e4a1e52a48edc1cf5b1a9e9a98c2dd0804afd9af5d21cdf83fa944533a0bf092b1ee9d46a4b7950334f0cc7240b20d336c25728c319537918c4bc1	\\x00800003aecff63d902e4a1300f44d9e85ae2148f1fecfae889c4635c05f957ad173e99eb4bf804d553cd48207b23765e52bd864136573513ac9deacf940699422df6dc62e4b381e55800965d644eb607a85814706608b389912ad1cc0f22168287c513cccb625bf563440439a528aeb423df9258949744aadf4152792484c55a81b4e03010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x95737270b7d63baa96da47a7bd43db0dc01073b3bd80c303a34285a599d26d7cf5afbe9a60db63fd3efeca21956a00cf133e562c20a5b47ab9647235ac908c01	1639371212000000	1639976012000000	1703048012000000	1797656012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x8a515817f7f4cbcc80da5234ec435d221a732c2e35ab6a696de103cd0faf20362bda48266c6dc73095c6210166178e0b12c2b5ce822a62acafdc805261de89e0	\\x00800003b73dc78b52e894edc5489769514a63e8e464234a2cb9c26a84582f6eefd247c85a1b888b030e42f3185479c769cf55db042e68da03ace2cd99ccb2e7b2ce0db82907d52f01a6a5770510443b8da749983538b3270cc2ddada9e40c07ab59607a5beba8149d1716b800fb1066cc9d2e32d1f6b91334752c72fb4bbb7cd4fc3fe9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x33644c859d4c2eb5815b96db454b4557a2af3bdfad0a7d7307998f7b452f310e63b007eb1c59b64ae513a74677af4f77a4bb52e9ba1af5bb95739671099c8402	1616400212000000	1617005012000000	1680077012000000	1774685012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x8c1d9b990db21e02aa8cfc65c489810e354f1313331eb4a0f16cf9334b89004c7a2e2f731831dcbc552064a726d666fe0a08cd61efb7b4c20e1c1d9f3ed560b8	\\x00800003c2b56192fb3e64bc9f87d46189f44dc689db26fb591d633f1f38232b662d2c0fdf6567d01950448143cf7a01d1d983cdd0020f7985c0ae764528337257997a51fcc1b746ab218ba9d972c794ae18cd7107fe169ff9525cf35a7fe006bbe93f6165cb8f5d7c4fee029ddfa5d95ed6240d69338780a0861954eb7c073bd84c3669010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd65d14c387fa41a44fc7c18c6f9a61e5c0a7ae0d5c76e8c9c6c0da1b0d2d2231973934dd4b6c1a71bbfd47252cf248bd15d8306451b3e2b098123a1afc4bbc09	1632117212000000	1632722012000000	1695794012000000	1790402012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	153
\\x8d0908f046c331c623014da8f8daa18f584d66733327d4012a1f41476137e7af766d4c8d17c9db4a9c6833201512418d4ce3389d63a535a5bcee6d362544e040	\\x00800003c10878196faac5da6d568a9fbc9680b366159b3106345b50856601dc9791b8ab0ae28959fc97e5ef1936c31b579fe13b964d88cd4c74c2a6afa151df2aca4c023abecfe37fa35a0569e8b239fa1773ec4f5ee556ed79d9436ef5712c88ef54a2767f0854a32bae76a13efd4e8631801fb29f81389b37e31fa95b7ff4555513fd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x239b7bcf6832f1a6c1739ee870246d736d20a0ef032a9f567b0bbb63728ecfe3b61fe02ead54e30a066a2958f2f882af3d4156c1119feafd4c1cb0b681bed300	1620027212000000	1620632012000000	1683704012000000	1778312012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	154
\\x91dd367a481f85c2ddbfc5a3daf0b1c3b191e50f831cfb383f032beedd74eee3b5b6d4799b7e1e328b6326847d22867cf9b57cd30f91a9482ffa611ef951b82a	\\x00800003dbb3e307552a986e3393c6662e3eaa8705f5fa717c482860899421ca4a8a2e84cada821db77772d5896791ee04e0f6ff06c02e44d061727438bc550c293bbc32cd91e8853d9bd755a8d640f742d3ff33fcbe95e32dd6c8d1026e4dc06ead136b588ad5b875c502d465e46ca3755d583b1a6deb848f5d5fc0e455ff6dd42396a3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x70e6211a37217bfaecc6bc6622fe93da6fb12e16471abe6cffc7c6939c41a8758241f75a4cbf5a43d67b159d1099bbfd80dbc149e1288433fe2e5ffda4bb0503	1630908212000000	1631513012000000	1694585012000000	1789193012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	155
\\x91858fdf0504e99a6770d1f110451fed8a10af2b9e0dff310aef17dd3d64ae7e6d4cdc5960d1cf36825166d93a58c430143b0392105ab4cdf0ba7e4ada819c46	\\x00800003bb215caa00e9bd5b39ac632b8d783f437fb159707761eed30b87d17a167d585088320549ba19636f2d4077b3dbf71b28f060332c41b078e66a283ebe42e722de7cda77d8d56275a3b7f2f9707631f9c331c924464e983923a72eadfee6f50ade8a34a02f61631cc22721ec2a171d49792b20c5b50758574e712e8a409dcf13df010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x16d09fcb576172418172bc1b8c733377ff358c1a1105a1b5a4ee6b9c347ef5c411ac0f29cc5928c5d6ccdb3b33762862d33c11635d9313a97e9cbd390b65a709	1628490212000000	1629095012000000	1692167012000000	1786775012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	156
\\x93bd057e269169ccadababc35769e8dc0e46acb1b7603c802a947cc0a2ffbc82b8e4f78a4eef4def84a9ecddb2be0a1ef1bd8512a8f45543eab1de3eef5d7b4d	\\x00800003c71616f0faec3d478a886c04720b529c078bf612d7bec11fe9771a6e7a580a6254f562f0cfbeb6be0ef0a56d5edf57b7cc7fcb78f709d8f8dea5957353a4c58f60c930acf38c4b36db2e6f22b6d0355da24fe4e647febc452a2945c171d3719446215f8b66be2997a37b2e649c7cebfd5389853db6e7d7279d612a9cc56ed77b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xec531446932c26fed13986fcc4eed499dd70710141172e863529ddbc50aedadff276f1b99103839638b8768d0b2bdba9c7b9a26ff8943c84c188f098d117e607	1621236212000000	1621841012000000	1684913012000000	1779521012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x933d2c93a1c7ff53b24e02ed60fba9887515804ca40aed70e1576be31e997cd49af12722a7d14f56f3ee919c24e7620caacbe90ded1a50cb20eac90599606664	\\x00800003d5b22819af5feea83f31535511f8028dce94fb9f97b70d28bb32cec60f6381760319fc107945a858832b71e2404570536ca9de87b952089b0188b31c26acf791b77de7bb0ba12b5375ad57c50835ea5b1cd4ba7dfa9f85c40370089ffe88f0a09e60ba2331f2dad400628f35d05cdb44db6ba6bbfe53a6a0c045c58b8daf082f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4f3534ff41a818776ff0b74a1735990debcfa9f292cb9e9a1c06b385d7115467638d9aa50349c88db0710df321dc08453a874576c4337129e43d6372c195ce0a	1635744212000000	1636349012000000	1699421012000000	1794029012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	158
\\x96355ce2224a4e54266d8626f7e833a19c795e0070e55ee90eba8a201245e1e33ae6024598def3a4ef70053011d1b66c836e75f0c55896cfcd5c295e08ccc883	\\x00800003b569109f09f5f4c82e7f7f4508789686e35687e452f411c3bcc5e5c26306d980bc0960099f1d44478e1e7abf1742791c944ab4716ce21f7035cec55c69bf6d17ae3d3827e16001a4e2f1e0a7406516bcd141316dbd595950d55c082ce87411c718e14c6fddf784346047823ab7c890f13f33625f7992ae3ae2d1fa670193a2bf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x470e96db08f3797eb7fe4941f73cbccd8fd546787905152a66a32ce2b23b4c6c0446d5421b101429aa430f62493ee8c9635a13f61b610838dffa95fd2baf930e	1624863212000000	1625468012000000	1688540012000000	1783148012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	159
\\x9865eadc7d80fefdaf2188916b1793f8e3e0ce718d9d1e8c3dd76335744661c4384935114dea483b8d2a84164016e3738cda8020a90ddb4e4fd9d4ea30731efa	\\x00800003dc0e5426bca0aff7489a51b99eb58b6e25aee351f1a93a6cc2fd2f462c1923d096bcf95dc648b06778becf13194a067182aae03098c6dd5b49047d0e912ed308bc1ec5e79c27d4a6eef8022716c1fab71b7ac03e1d6d72fa5b253e72011a5a1510049d440bdcea920d9bb198bfceef0c05b5648df3a0a93f07f4d5a80c35b867010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x41d85f16be14c739d4571785fd29e0bc2c4b7bb312e37fcdd0c020936a1c058d1859f380a40fdf4b312b58ddd168b5a331132fbcde0159d1133e40e3f291ac0e	1635139712000000	1635744512000000	1698816512000000	1793424512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	160
\\x9901f00eac0875e707a762559db87007556a3a780f0497d26b132ecdfd1e21946b269ee1ee08354d5bbff01075332df60f4b4d64d5a9673c57e906d4df3f25f1	\\x00800003ab82cbcbbfd84ee9b3738ad9c2bba3ad3b9ca2bfb3fcb84863dbfe23aa2d074587ad833ef966ef9d4d74b8c517f074c744edb9f6a307855233d180068527ef5ab68f5c44f0093cc4ad8dc125be4ef161d840d86152251c7df97b229abef100e0ab75c98ec50894c636c1cf0eff62467339e563b225a92025a3bdac8ccd96d46b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8f32016fe932c51067126272df07b71d4411c6141714df3898b6039df9b9ede2d2004891f6343638ffc1d35d27c3b32ecf0d6a0c850005ae8ec095eea7d1d401	1611564212000000	1612169012000000	1675241012000000	1769849012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	161
\\x9b71b2f6c6ea7a10acd7f9ecb9e05bf112138f6b5415329aed7cf482b83db8a6daf32d3103300dd5548f7a95c3edf3d259640eb92cbce92fc251612052d77830	\\x00800003b5e6346f2693b2d6a7c29cb0a4d82332df0f038562d1a238a19ef9461e2282eaa36d0ed062c8c86c05bb2d51640005f4ea2f8046cd978b3fbc1466f9f53e69345a15f4bc5589c2844c7bc485a0273834f11e27c9c5e0e9dd2a6d792cfa71a3044020dc52f0ae3bee052afa674e56a972e4073ebd6e41148043313292c7b11aeb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4f3ced5b85a2009b35cfa272183fc236089e3b49db4b9d65ec17c13b1f9805d509271589015f697d57bc0e44369984fd8be01d5f00cf12785d3742dc3b005d0f	1614586712000000	1615191512000000	1678263512000000	1772871512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	162
\\x9d3dea104d405e9890708f23dacdd6e011f1f640d922d39af67c9edaef61ec197b69aa2001d15ad61dddd772cda60f749b0f1c26937eedd5b3575c7fe2f6e0d4	\\x008000039cf9c34d81c6f973174ea0e06fd57f31c8cb39c64d59cebd88d8271fadba524d3e2512ceb71e9b83677734be66193219f3b76ba17b4dc80b82d4f0bc7921b369cabaff5cf093b575a14f6721015315a4f93b23edb92b7db8ce44b8281f9607d9a73616e459034ea1e629d527bdc85774e5d515f259eb4d775ecea559ebaa2c9f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbac92b8f45fd58e8ded2655344ca0c69b0fd25a2d770784adff65e65209e751699af0c4c092d1dac3a7e5946eb56fd23b507a4ecec6c4f1f7a4840a0310c200d	1632721712000000	1633326512000000	1696398512000000	1791006512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	163
\\xa2a1e49340f69f402f72e57d3325d3adccf3883832fb4d8618dae44158de4e35b6883f9cbe75e918b4f130cfe0fe6985c0ce1b6ab9308add747d37e31ef11818	\\x00800003dac4752d5969538469b1d8cb623339803037a3f93e7b58c8ab7342837c8839dd2dee6c5462043f891d1c51f6125359c6df849e92a5dfe16749052fb013ce87a6b4343d2478713d4cad19b4bb5db79849c30953996032254b6e8b3e1e827866e6360716a2df0ff3bf17739ddb7870020dc52bb8c65eb73d75e1393b3348088f01010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf80009f73133e5aabe606b137f614f0e7ac008d1160f8c2b91c9bfd1ef54c2b432f2836e0881daffea0b7a8d419cf85dd6f162d46f77917f81b7dcb4fcf5e207	1636953212000000	1637558012000000	1700630012000000	1795238012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	164
\\xa41191bf63c71c59d3e74c29c7b36f2350df7302449658118a132e336b58b097b1c3d7270c2ef488341abf854e903f7af5da4f27badf3807588251a698f94a5d	\\x00800003ee00df337418c4654700f1faea5ad33b82392f24b70b80f4848121e01464809b69664f9d610e179028e7160205a3d32f7094648fd673e12c07a46a26c01cbe15bd8fca4fe6e02833a8c8f6219ffc10189880f4a8c26f8c7d5ed2e3b94dcc75e7e462ea501ba82bb79aab29250093a5c4765e23f9bb23431a1795ec4a38af793f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdb6e86ea332956125ee64f6707b9beea4697048fc6944a0107fb217076ac62413f6fd8a47f86397d00559afb65849fd87412d179f3a5b81aa1d9a29bd4ce0406	1614586712000000	1615191512000000	1678263512000000	1772871512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	165
\\xa9f511b2edfa8220dfb86e80440d70c8b4eada0aba5db1fac508c9cecd99138beb96c4ac3378b4ffa2ad03a56b2257a4a89112dee1411abcb8b516c76e956b38	\\x00800003c9fdb5422ac6620b43f3b43ecdf8ed5003eb3b6c2099285d48a05d9ca00065238c6bf85d4c48fc79ffab0ddb499010424fdb2190cb298b72bfdfa894bcb0a831f94bf20d6246315d5f9f1d7bf6aba6e8b9a37823f6fb6da7da7915729d5f8f305da4a90ef06d748371f1e5b69d5f1a945714e243f01fe6f2c18968def1fd825d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe7de7fe0ecf5ce76f30a54decbada40ce74f55bed465d4348a9e86244f14b966116795a191921f2f823ef07f36a86739fabaf058390e1facfaa0b508152c2005	1633930712000000	1634535512000000	1697607512000000	1792215512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	166
\\xaa915431e34c64f9932345fcde748b8ab9b90d81bd09f2eb5902981dd5dba6e1b4f74edbdabd55e81a6b04bdf3763ba139608a9a153272b13bcb7bc0b88196f3	\\x00800003d60d695651cb11dff7a7b1e288e49ea23c0c94796925843a974b028bec64ae17c0f4da71712ace517d6a3b1931a0c39e9d336a82e270cb470089d38db0f4af1182270e32e1babd6a6df8a0a099a2877364993520d609f343e92e7100a3d3cc7b01c68f8f67aa3d64187ff3f1a65235a7dca9aa64625a86438defd4dac2bf2fdf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc83037fe0eaad6956373474f4afab3ed3e997413ce16b4b5b3e0c6c660f573e59cacbd36c93e9f7c4bca10c4c9d351ea2ba66fdcca5901dde46fc5f353d5a903	1616400212000000	1617005012000000	1680077012000000	1774685012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	167
\\xaadddd25569c946e5744e01f9761de4b6663ac3ecc893cfd24d15f4b65c7804e79bbc11ba0d738ce1fa4170d418073633624ba844b7005d418a2df27c0d3890c	\\x00800003b52d17afb895484d122dbd683fd2fcb6a7171710fc8e60b61fc04c69a35d59db5806190601f27f08013ee05835b115bca03a55afeb6b19fe7a4c2e12b1168e429fea9c9a34f244fd9346f8093738bb6199825160679e7ce433dbf13a9fed8340d606e0d6a6f8e783252e1cbe8af133b7df716c2e70ac41fa3598c31d14ba8203010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x72db8e33847392740150ae86d5c262d498cd1d92da8b01dbfefee9d43da30ff21bcba7d25ea885ed33b0703082b558f457bc2d23f9afe88822a0520fe009be08	1636953212000000	1637558012000000	1700630012000000	1795238012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	168
\\xaab5caebdf607e270dcff0ffda462270b76e47fa2a61eab63d9fc885b843d87cbfeb71aeb4563d32079996bb4fb0f49107746e4e6c67478d230e369966a4c39a	\\x00800003b1559ea33064afa59632091f7ffe749d9c28182fd8e979839be6afed003df0175b216a66b9ae1ab716bffc091895775dbd692ecda2ed45563605390e3d8ede6bbd13a7ea577de5fe25d73a8ee587847b75bd8416e4c5cbe321d6ce30751a0960bbe792601dde71eef53c394593d6cf63f07fac42258bdf1223f0a90bbeba02f1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe0fe368c06f70c4c77c590bef9c6ef2452f1c68a5bc819f303bed81ff82c294c23d39d0e67c4ed8fdbef9bff4b62fa978c5ed05e6a94986400f5bbf3688a7406	1621236212000000	1621841012000000	1684913012000000	1779521012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	169
\\xac954b56191d3a09185962f9b0d9cf40de9f8c8a6fe79fbe18c4984424d7a8201b04e5c111dfd30a9fc4dbb3a1b15f4b1e4e4b120a3a10df64a668a91bb95196	\\x00800003e6e4d30900642f6247f2789ff3d67367c63a9953e458587c78dcd02cdf0a24e791d2a397a7efec0a94348d900beb8579bf0a4e5aef148f6d8dfef24379f7cf8815ad25b1b6a0af66d06e3e5929e28f30071afaa33b90809df2de25cad03ebb9d432e5484fb74a030fbad4623f3a6c12585d3ee6fe25e365a73495988f006e09d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8ff8b8f078aa4d6135bf927dc16953bbfef7e498f2f8252ae98f21a6659ebd53ad5ab7417cd0b472477cde17e483717c007be8e0934ab1de39126b4fc4e2a20e	1623049712000000	1623654512000000	1686726512000000	1781334512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	170
\\xaf3988a6f0be620cec7a0f56e08747aba9959925819ddb9528cc908fb782581aea6dd0618859b25dad6d84b0c4f66842acdabc75a6e2b06780e0484ec09ec5f7	\\x00800003cd2038d50ea47cfcdc7a696262a0e0b418d7b90ad28f5a86a583b79bddb340b9593c5e449c3b176299ff75ecc152f4676153cc1b2dcf1a388a7b5681f1171ca40c6a6a1a8b15eda8cd5160c64b5a3807a8c97fd5ec8c350114f41822e141f6771bf28813ba3b6c31bae849d4b07fae01fa05dbf04e8d0a2ce6566f640f5bc0f1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x50d33e02ecfbcf6c9e4b0cdc578980a8f8f4783d0b6d72fdf3a57083f9f7ab8b896d8f615849870d65726edbed43935fcdf8d0b2aba388db7a8f8c7f6aa2cb0b	1630303712000000	1630908512000000	1693980512000000	1788588512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	171
\\xaf594fe86568f128faa6e302dbefa29e215c6664424417a84b0e1b8a631be3dcac3e8a9b8dd38da6916c70e3e38bc30f71399d21f28a6a819c4c84d8aebe542e	\\x00800003d9421734210e3e6d9368deb57cb0d195f4f9bcfc67cf4626c5cb9ede071b2216391364b17733d20493ad2506ff545f43bfb47b693995fbe596e71670d34d0b385b2f820d92e979b42e91c85b8287fc6c83a08150c6f56c814ce0120f7608c375354710fd6856ec6cc73ba8225b50cbb21cb53da3e1792ce84c41430555adb5ef010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb765e40f93936000ba8da653be09e247ae325fd15725be6082d72fc85bf4c4e582d0ff637abe5e3aa8c25f53a842eaad516603275adce1fe699a8c84b467ea04	1641789212000000	1642394012000000	1705466012000000	1800074012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	172
\\xb351abfa2b096d37980a61840156c165e53078f1684ed6fa0f369cc70c59205337128734e4742ccc7efb2d57feeca12d51693ad934bfe946bc9f16bab0d474cd	\\x00800003b80ac688f9fc5ada18073aa099e05908408ac895b408dbc419b1c232ec1a79144151a291abc6fd423b3ee46b9cb954cf781e5187702bc3671d448b37b66ec8e6c6d605f4c224280d10e5087f578fe7edfefa9229d5e3660f25ca8ddb5a4ffc83c2eb3e7c314a44ecc58d60e24dc3a4f8d783960adcb2ac7a13702271fe1646b5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc1df4984e7f1be5138bd013e9032a7d6750a3d9274fc6cec653de2ae7fb3e527a0feb153eeeef2b2d3c45037cd988aa632ad76a682f17cf13701cc518022ad08	1612773212000000	1613378012000000	1676450012000000	1771058012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	173
\\xb4e5c72b0abd05caa92afabee469cea6badc71436eb7a0d800815fb1a92871db1949992d9e8294121ebd623ea70d015a23146899c931956a0f96621d35aae829	\\x00800003d1c07a792076e1fb25a57c640da86a8ed2dfa543a3b9677bc3bbfe4eaee416c0b12ad074e025cda589552d15b66734d821fdd8874f56f90c1cc57e234e0dc7f3f6c67824929391baf89f3ae425676c8b93b0a1d0dc65701fce57b8f58410d54ab8413f86fcfe82bd84794fbb9af9988c6a1f47c7298f2f139fe34649ec3fc21f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe874179c646ca5f308bd00187904302526f96f0e090cae4c2aa9118cbaf4076715ab21d50c50a88c00a5ebe12b1e27b856f0403930629532fb80934b24ec9e03	1640580212000000	1641185012000000	1704257012000000	1798865012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	174
\\xb4717bdebe03097e7f21e1e7fee752e91a82158c6d980f761710fc3ef438e16c78bbf2f7f24b366056457a9a1eb681dfcc05879a67b4335e77a5d9e7a5551c76	\\x008000039878b539758db2b78a2d176724ffc78613aa3c586084b5e0b4b4a203a56be2dbaa9234093b5fc3b302fa0219b251982189d74a31ccb285b90c9448960ae149bde577be362a37e1b66182afeaf46fe09956e3b363033552420cba947b13c1822eb9c2bf2a64992219ef97c41a244bced92b22134f37f5ef08b38c86cc1a63ba79010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x210167a5a25cff58c8b7e6487f29efad9c410ba6ac9d01ba041b54689b6eeb1a97527f55227023a75effea91b59a2c03466bf54dff920059d47d41a0b3c6b805	1639975712000000	1640580512000000	1703652512000000	1798260512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	175
\\xb565eae0610ac09d56cdef3ef3d3f37021e5e25a3330e134905fc5fb5beb9cb67c6715aaf550429168b9e972f4772624abf240bcb17b46d63ece6b38887807f9	\\x00800003af35bb593887da24a6919a18e712466c8c70f4ef25bb7fc10987a0c5d2f360c07c60875b874e32ec35eb247e69c51ba3b97c41bc987d8a9d81aae3d7754cc36418c666b60b50453184de7b02ff905bb8a2fc743f6d4513ba962b03616ed96a681b60321ba0aec249798f0054a2d39e3219725f85f4d0f06714b7530376b69eff010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe96715bef39d5248c4e88838a8878a18afe4634cfc932b563bf7dbf2622fcb7ad5e081c23da0621e6d9040653cd1ce9fe6e0e8fd84a5775e1eb4c26373999f03	1610959712000000	1611564512000000	1674636512000000	1769244512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	176
\\xb821799ea922d55bfb863599a94ec2bc3026bbaff62d2d69ae3107af447cf3eafa1db2d92dd1fd7fe51537f89b25e206513c977838742a1fa539b33572e0c630	\\x00800003c849ad916c0bfd7ce573f04694bf39796b36ca6b6b60d3b0845c55d4ea6a9826369e36b72c598dcfc13b035e5e6fbee94c6a8a086d633f328a57dab3161af1fe89b834308ad57c839ca62edf292c6199f4361845eb6bb9136f626ed58b315a4a8fb42275fa755b7111d6dfefa54731eaa5e88a08351825df2621d9ead7c760e7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x11a590506511d1d3561a9020e93680a6f5276953092ade4b88cc8ca4ecfb3af1c59a9a2bc03f540b22a4feb4ada4a178df9b9d53a78a98bbbdcbe4e4615bbb00	1638162212000000	1638767012000000	1701839012000000	1796447012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	177
\\xbc8d22528a57d2ac8a4f79a8e13d91d6b44a3af16672e7ff35eab551e175e7b32548e52bc6d26dacd8795518c1e4f5bd6b0426cdef5074e7ccc635bf184b0a3c	\\x00800003b2d9ec7a3189b948a0889340a2418e4ef9d8cb1a74785d31a96e70f9cc7f0da10a3a3b7c4c506fc5062cf0ece1a63ba87dea9048e9e50e5de9361f155ed51b0567ef06ace4f517adb29e3391e0626c3cb40939bfb23fa6bd186d8272e9d41a88f39226208717a833919ec3213bef759926c3762e121b9a84e6507e41172b2603010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x56349389c15e7144318c9e4bd8e7cc24bde10b6a68acac2bc3bc005a290dbc6ee0eb11688ae2af9f18add33d2eb0f98389f2d2e6e4e131c8ffbe86a1d6035109	1611564212000000	1612169012000000	1675241012000000	1769849012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	178
\\xc069ab84e08f1783ab22903cb4faa71acd2c8b303b32911e901edc74eec40ab79a41c58bb780ba83a7563f8ee6e699abb90498d54d7bc763bfcb1dabf604fdc8	\\x00800003cc3e8214089445b1e7064d75da20ede6cd405136f7dc0496924405409f359481819245491cd4b22e4984a8516573f3c8d2e31b7644e66faabce3db82bc986bdccc98960d2a938f8a7b04d43a8a53d807d98544f156686fdc3d41ea62add2d32414aa60c1ea4e9e74b6da89b8be857f53f7ba27ac24085000d1f0952f951b6a19010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8b55cfd083f6e3955aea7e6bf05a3de0884146848ed92fc98ec3a52777625d0605ef225aa176b36f132b04be1c75bae6fd680034f68e9e059a6955482d39a201	1616400212000000	1617005012000000	1680077012000000	1774685012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	179
\\xc181fe4a7d851447701183a9c155a9d2c0e3eb8a21439a222935adb790faf28e36610f75045b315eb4c27c4663e8645287a967297ff256d3f697a2c5a2a7ab9f	\\x00800003b9c58b4b55162f25a02431c9e0ba626bc30c5fe82cb957a19340a1c34302a6dbf3a84aaeec2410d793840746f8de88c72d93732494c96708bca8a8ff822690da1636d3e04b75fbf2c0f1989d17cf03d2c81f350e3e672a5113c1dcc89805a0e89f57c9b4ddaedca56e69fd242f1bb684bc7b1ab70028845e7193988384a8429f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7893ef8c4d6ba10107c7df454d9aca09f78be525a60b62da9e19a7c94a77b8957ae19f15f7d1817c574c8737e5d2b25f45c7507b115687f478f99398ad169505	1618213712000000	1618818512000000	1681890512000000	1776498512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	180
\\xc6b9006e87422dbe75d434010cb438c82d20690c1cc38f1e0fd6104f42defca0569ee0d29693b6edaa78ebe397ab6b51cf33a320c622f9ce4b7673cc2f4cef3e	\\x00800003d75a0252da47e3b92f6e044a12d84b0ebfc631fbe0ce28b1d939cbf58fab2cd18f15bedcab149aa6e7af8307acc91c7dc67fe172754e293ff3af73a671d23d89fe28d32f9af9bd9660ab5f42aed2aecee6d29f1a767af3c960fa5afdd0ff1847f6ca0391569ec3dad47d2d87f436a7ef879f4841142ad935350a4f38319d6161010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8974eb3c470e9b589286199b78eb555a6b21073bbe4a01d1630aeb6bac9240e4ce61a608cdf99a95c790fd9bafc602d9a14d228d14f9d330073b151d42577006	1613982212000000	1614587012000000	1677659012000000	1772267012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	181
\\xc7a5fa409ab756035f365b6107646e512bfe434220c55ec7e0eabf63cdcf559149061949848bc8fc7d5cc7d8791a78e37b613cc1761b0a759f1b209144878364	\\x00800003e0eee90d870258a3d4c5580d1cd4f6bdc14373bece01c48a3a4c2a78a4677abb124fd678fa5f1f1d7d43a8827a04021e001bddf17d77229fc401754d0b011295d43b6f930a7ef74597348807db48789320dda9877caf4628b6d7d7273f310d63fd7ad34adbd0f3ded9740f8d3a51d70cb2cff9ae07089cdf65a9a12821e0c233010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc3398bae2ffff7a112df7ea8ca2737b95e1631cd3c87e656fa9046ab105dbbcc3e1e8fdcbb80a0845e67add891996427dca47ec2c0c43ff3e50b3230ecb30207	1618213712000000	1618818512000000	1681890512000000	1776498512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	182
\\xc765c0ff87784b158bfa38c0d334979a3a273218bbc03007f150ef83b9b6ccd221c4d8a10cf600841b8f45dfd716dee17dbbcfaf5bc96438fbad3d4b7ba0b964	\\x00800003dc528c18aab21996d8bf2e0a02eba488075bed3e74198c567270e915b4c0ac0be2b02a33b86fb5aaf78e4905c1ed24c606574be6dc1fbcdc7d7a977196439351b97fbd6a1ca7400c42c0ba2db1396a283c2baf3e7d46ae9263e6b5be228f24d845faf4a64dd8ce48eb0ded719e428d04c62e2c6b305fe2db9100bab5fee90355010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5b2c69b6ac66bd1e18c38c4145b5498199362f92743a06a9332498e42c11ff0ae41c0912ded877dabdb7c829d2fdf5ff3053480aef53ad55f5b5f34d3f577d0f	1615795712000000	1616400512000000	1679472512000000	1774080512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	183
\\xc84dbc5aaeee229ec681b8b4d3168902e8985fdbd5ac26e1e5c44ec49a7ead3a48ac278f3c30697edeaee28869862256fb6ab6a4514f32414a6c7d19c3b9a71d	\\x00800003d092f5a15e4daa4e4b7d6fc3b0442f12b89fd5116451e354ee7b351698def81d98edfadc5d55a545b029d79a73a49802e9e5d4777d52409c363510c139350db96bccab4850f7c63f3887f5a95c4de4cdd6cb6d0fe482411191d451476604e8745a41ffe86d2c700f443bcfd96176da0c60da72099088d6d6ae5e6f942bde4879010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfc2667eb9aa4f11da64959fce93274498746119959ede2b6a3704d419f92bb459e457df9364f6ab99818fd0b0d59d7a6bffeb10aa23efec2a9dcfb09d3022c0c	1613982212000000	1614587012000000	1677659012000000	1772267012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	184
\\xcc090cbf0a2ce059fe34f6f0f3328b24255d8b430098653c0decebdf8e55f1637a3ced1ceed42e29daa1381657ce336502dc8d3caec096ba583535b030274f59	\\x00800003c13612ffdd9a9687f3cec11fe3ba8b69d763a6d83d152f559b324a856d6deeb8c408c9f62fccf2a189e9dd63aca549f2578158e2f1119d428256969529b60923efca9ce25b172f31e7b89e862bf1c46176e94c891486ebf52c7a35fc4de4c3ec5f6fd3e11f80f1a4d7e6b1242d47860a2f1ff0e86bfa9fe6ef0a9df04d602543010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf674b1bbaa78aff6ff46b92d89d277eb2e62c51a7287c39846d2277d651c3fdaad1bf762f44ffd3e60a6e3521dc4994917ef50b3c6561c5ecee3e793504c2f0a	1615191212000000	1615796012000000	1678868012000000	1773476012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	185
\\xcfad2884dcacd9978319ab6badb4f03ec76d9fa4543d024a8ff1192a48a1dd0f16f56895b4cf6fc7b43c4e1f086e74c3f64f8d83027ad2865fc9546400f926e4	\\x00800003b98b32bf022505c8df7a7696b3d11ecd7d4a20fb7f7377ad93ee5d5cb5af5423a132300efabd37a5d1c41fda1fc8aad4573fc86a328e83933b6fcf03aef797129cf85f322e3f352df94d5898a128d8fc652f7537bc1b4d28ea176a454b8de304ab823dd23e0e769c1784450f06f98af1123eecb4517a69ee399ed0a06efb799f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x90973fbfa3a8975060b3737e3e0f212fbfa2c9cd698f799a423e3e7dd5d53416bb78c9429ad77533ead4f72ac8ca2ecce5924bc4abe61e36ff963eb941928e06	1637557712000000	1638162512000000	1701234512000000	1795842512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	186
\\xd181bf97d68c883a3de1a52dafdee6e75c60dfc465d36f4a975ee252fdce7f1656793f03d5b62d55e8f24749238332e92a44c49499d22bfade1adcfdcc7221ec	\\x008000039a44bdf6efd2c9ee9c3b798ff9e7669acc84c0f84a908da5b760edd171b1c63823f5292c210d5de9d4bf1d037405abefe973f5fa28a8a2689585406f0ec0c60669be374ccebda8ed76d694e2fe95e997253ac08d57c1b8528ae4b25e64dd8e949ecaf6c8b7e896dbc724b872fea6074bc4b4da32fae90f7b5c31ad483ee6e60b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x40220fe29d4501d2abfbf64aedf61d114d4e727a0197e348560c867452fe566ec3a6e966d54f352cbfa4051d3c4a6474e2a83daf944cf29d8a85804a43868309	1627885712000000	1628490512000000	1691562512000000	1786170512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	187
\\xd3f1af0696098daee7e4b130f6a4f91a62231b09be7954c01e610d9b257fd16c836b0c94c5ae0505c5bdba6ac7a08255ee0534ac3a176fb29c10e63c2f033e3c	\\x00800003bd67a44342e77f5ca14cebb4837fb0c5e3d05bec8dc5858e9532a256a1f17f87aa7755df311a0079c7d53cc04931f9699accc81b65784528f09e688227c485d1dcb6f0f406b619a5a496337f6e1fc27f1195d4ae0c258ef3dc216c3109753929a8cecc92147203bd4081eb730204444dd3984d69bee0d6696c3e3a9045f2476d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x862f6cc49a9fd65a3ddbcde0546346d5a5a5fdb5d998ca7de795b06ab4b012900e8447fa047f811ec52204d5df7b56a1e2e2cad6e9388ec8e596fb5190895e02	1631512712000000	1632117512000000	1695189512000000	1789797512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	188
\\xd49da71708a6843705be3f3033997cf2a0cab466dd386faaa07ca76812af4f3ace8ae72cef1e245ff39f539d9570e1b3f40ceba9331f18c432634f2819299d3b	\\x00800003e32ed6e5733148cd0c6c7ae2e6ab5d2e1ac6bf852ea71b5aedcd5f899ad93777a1c20716c0ee6c9087ea4f9c3e64b6421b23483dd4968325e34df5796cc5a0eb4212e6c50c38a5c925d31f37a5e9fcd05acf219aaa45a78c4f42d49e2fad5b2d402fba234bd82c86c9047c20ab8f1209d0a5fd436bccb24f80be9d05b49aef29010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb76b27f9ff1c05022ea209a69eb2a6eaae3031edf5c0afc10f4ebbc57571a6834656b4b75ef90b91e15c625ad35063e8db4a087735bcba96b8e4a279b2c9f607	1610355212000000	1610960012000000	1674032012000000	1768640012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	189
\\xd5d1b9c324fae9d36a7d38be6361ffde1596902c29d27adc12e3fb2d4c36473191ed38c5f7e76e906dcd9deafc35bf8b1bb93d1c9e9780c1d4f4d8d99a7a88e6	\\x00800003e7b766a80263aafd778e70264caa44aa7f79a74ce01ba3f51e3a4829d00c2df6ce2ce57efccdef43fa6a1faad1453fe93096b3815a45a020d42239f958e0e776e964ed2295afc05c8aaea7d1752d65b95e9868f043380799ea374904bc0a8b2da6fc639bbd153ba0fc5e21a740d3e17e346e733d8def411b5b01058689bca4e7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xffad2ecf69e858734dd51cadbfef1c40a9cd2cc314b39ce93e6577c8d8801f19d3a8ed56afea76181fc681ab209c7f84d82d1a60559919b5f13f2921e6a0e80e	1616400212000000	1617005012000000	1680077012000000	1774685012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	190
\\xd6615a7b802f5fc70e8b6911faa1e3665cc396b255c3ad1415e2f026ff79ad98167c2fb49c37ec0d81827b58b4fba531be7c707fbb37bd0bd74632696963fe77	\\x00800003b9e035429812e11fc532d404cccc74e6cf44ea3d8786f4d11375aab9a390986201b96651bf815c7b50ef0c0872bd1ccb684c178a226fcbe1bb06c78fe0f0587a285e9853b86b58a0312042526e133fa1e098d520c952c2033de701969cceaf2c91aa1fad48b445e69be1036daf2ea888302107b711250af4ad3725909f8ae205010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x45b6d3b5594ed9906c6494e321da0496e39cc2605ba1dfe7cba4a7feea7e1d0c5268031d752567414eef59df05dd6aa909cb208c18767ad6b3c08c5e3bc61e0d	1615795712000000	1616400512000000	1679472512000000	1774080512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	191
\\xd7b903ebc6e781bd5d38a1c185904bf4aa9fafa2074a6a824112b122c14b7ddd26c50dc2ced4e897b584cb22340d4f344b6cd38d27f5d9b1f1a83bee0c200430	\\x00800003d5c4b58a45e94d597a3af67bb47eced710ac4eee8d2b05f735a5d3d6f47b281431aff792cb9d7ddc51686ab66b5a840572622b0cbe74dfefe5d75964c300abf697eaf1d3dc52f40a17899d2c8aefff72e911e90b2e2ddcb32aef93fd2a9ab328875adacb8528b844a65765a3091f27b826e92c3cfa974f8acf4d55e7a43e95e5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcd2fa96db8c0a251431c161a313f35b46e48137f1d79a99bde3dcad7f8471d4d41d6be7c700c3778d60f149f22d94b4719aed592caa8a6e1a19306bc3920ef0b	1629699212000000	1630304012000000	1693376012000000	1787984012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	192
\\xdae14c59034afb72cc8d65fb73caf0c0a88b9693052e9ecedf783831c41118f55530c3a2d6ef1d89ae34ae2af09a2ad7b0aaab80cc2ee5d85001c5ca9637d1e8	\\x00800003c4116410ed01ceb64c00792671fafbf92906990aaaca16aa01e0e6a3d9575835fda1b94bef21139d29268833c606a6fcd6e5434d5460a4c79fae92ceb547577c35e8af67b310f9214d08584bcb5d7b91c9bae7eb526faa64d5ff19e728d09d090432fcea7c1d53eb9e9d7f01a36770bdf3241e2d65fe2bbf2e424a72e1298a1d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd1bc53e0e5575d69c9bbbfc974f2e3d9ed2d81ed303e57ca1bf952de8ce503195c6e8971b704cf767b70e38d95cd61a5d0d0afc92f4d43ca7ce1e78d6a4fe306	1640580212000000	1641185012000000	1704257012000000	1798865012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	193
\\xdb05bb4fff7dc964e6fd0a1f45970747c943d0c9995519347d49814b8dff6b2df06b682afa6facdcc215af5f91c049457b6953fa8a12ce42f8511f3c2a61952b	\\x00800003d68099a8a4824cd72be03e899da1f153c37f69ff624ea12060486b3a7ff917f4985c65acad982a3b6c40e411040bdf9f5dabb2793eccf7ad32ae074a2945be05fbe7b2bd374cd8e0be34e1e3c8f45ed43b940bccba379685262e67d9ada33b4d80fb88ebfbe4952c14ed7f8d6e93a7de7fb01231af351a712396c75a027dd973010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x60ade5e366820ad014c34d23a845c6c4b7d24826d9aa95fbc39adbe0df78c3cec529c0b059d4fd57d83770a8110ef502220bc7662f4391ec5240bc6f0a443300	1629094712000000	1629699512000000	1692771512000000	1787379512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	194
\\xdb45adeefa1e903cee09f98653fa63eb7a7a6ffa47f1ca985dce361734512d2fe254de343784783ee89ece4e741c8e1c5decf7a46256483c6a0ad4aa6a01abed	\\x00800003b061ebcd71507df3c554ccfad9b91d088fda055f37b38cc31a0bc5202a34980f48c4cd2c9cad5d702edc5ab69a58ba03e6da944c152b737283d706b997232f3526f1ed14ba58d825d0e6c0aa72589c326ea5fe82873a44724ad9ed380021f9f48635f7f168fb58605e118fc4521d64b8b4aa6cb4f8c295325d284765662c7fa9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc7bf1a626b748186fb136d609c5fc69cd95cdeb824b44703493341f35089b2108693b70f067f722bc903517f9a9cbcc5641f6d1a7693a2665ab19772a13e1005	1639371212000000	1639976012000000	1703048012000000	1797656012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	195
\\xdc1596c4ced0df24423ed92e88019b59e025482118aad21efc2ab287d240aeaf08b24c155be332e7e55cc4e43cb2bd0a1a3bf9168b51afb6461a2bd78677dac8	\\x00800003bf5c2c4966a819a7c8a1fcd69beefb2467913f3e3501381cdb2f6f5c65e0ef8a74362ac02e004d130e7b30f0713cc0ed5685d9584bd19edfd1de2f0a03f75ef4bffd06c8d5e3c1b2243bf476583b2847340ab88a3d66f02e68c9e547547290c7f96262c2478b5a6d00bcc1ee69c94aeeb6f81f5da0cc077bf8a3fd71fe8a0cf3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc94e8df99972f71d87822fc376fb52a69b8689bf0df44bd11de07737e435a81d2c455645bd04fb2a56316aaa14d6cb39813650752c456e3dfb78b22f8d21c80e	1632721712000000	1633326512000000	1696398512000000	1791006512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	196
\\xdd113598414c9e111c33a82920470f20460a53d8106463b4562f952711c1ead1b23c8ebc5f1fe6c18f575aa2b904f57b36a7d19e7caed06233de19d93e044442	\\x00800003ab7d4494d7483cd501c06816e6d6c02a20d49040d7a721c2a9019e491bfb5db78c39febe51e964e15649d9fc58145b50f45ba6678d69efc4c955f96b150d8922aea285d0e2bcacded923d9dec75f94800a709f0129a088d857c12d57f4f7b0093bbf1c3715edb016e3ea01f3ac3673fb9e9cc9dc3153882a797817ca638b8cc9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc183092ef39b6de83287ab1e58efa4223b39e571ab5ac8728015742e3960512fe64ff5e47fb60ea5d2a47c3ae116df9c909f9d5915397740facccf8b12c30503	1628490212000000	1629095012000000	1692167012000000	1786775012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	197
\\xdff11a04e03569676a484fda3a70e2be197bc12538918fd00e6803ff5dbdc4ca7767a14174453dcf09b5d2ac9737ecd86827bc4c3ff42af44f87dd38b574367d	\\x00800003a391078c2ee8c6012f1ad1e4d3360f927ab9238fe8d8ed7fb247c322c4a9ad51059bc8810b0e5e775e303ad0733594d2c235f9f949236563bfaaea4267c523c38edf1d392177019916d3781639605f8483186558dc66118d448a4a15aa5b96af24d91f7fdbe93ada832d37701fb02eb28109ea640353590e117b22be9cfc6ff1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x792344683716e22d9c051748878cb24dbc34cbea8a1eac1a8b8d9b99146a9c23aeabd08be1c44863a23a79965e3ed3bd3edd772d9d60bf4d5b3d727e04610805	1641789212000000	1642394012000000	1705466012000000	1800074012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	198
\\xe0f11dc896153f8e5ea4b908907340bbb2b791b92dd471848af7a04fd8d9ac3d8276c8c28a14c4aa24e3f0ced4a6723c4bcfab285202a8491ff17d5d267a50ab	\\x00800003a302dc79123005fcfdc42266560c5ac3fd46dc548c2fd773742eb96287b7913f8a3149256042df0ab97041153a9c23969c5a76fdec695f6c734a4b70319f3d367fe46013a597d2263926b81f253bd9238a47bdc78cda6d4a06f8f0a5aa7fe5e7a1b90e8f1d5d8916d7f5f7646930f66129d54f7b95d273a1d33798b0a5dda349010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa878dffe540abbee8c39d5d224cfbbca0823d7cc5d61e06135177de19b95fff1f73681f4beb897e174f4cf368b88913cab45d00568bb310c9b539bf07dc3d308	1631512712000000	1632117512000000	1695189512000000	1789797512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	199
\\xe1391e7f208deae8099598b6f6b484ec60a2f9a90b121ddfae3645e95db61213743171fb24c7d4d2ec8327cd15e723de15d13a4dfad8e38dab73bf202b256834	\\x00800003d66b8dee4b7a902b8706682e29efeec838f468481b4ebd8d12a8932db01ab928b51f0e1a655243e1124af5a2de8778139e1056c4738f790abae9dcbb5c842eba9be7468e2fa9163ba4916c4858ac5badd20524ef3801a5ec6aeef8bdbcbe66031852fa37e3da6bb053a6fd3d412cacfcfa1b9c74166c6af7a2080e823b33ed85010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x06b9cbbae5bb680ba7752b1db6f6c69281bc02f2e440714e21d879c5623f82889d9d763b6eb9ab5b362ad347b8fd610f0dc7eebb73e5a61401374a7a1d244407	1617609212000000	1618214012000000	1681286012000000	1775894012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	200
\\xe31531bc3d72026459db7886b6df60887ad76c68eb28cafd00ea0d71ae5ac9841d7dcad3d8a1f926c31f3a23f3fea1ec868dfdbba97f447f1b2712c1622778f5	\\x00800003bac7713ce74a5dc3f5f16b8b539ae079ce9de72c46552c685cc08fd3ab0c2d71ffff49067c679b9c32a711ec20d19f05f5b77ae590e64e8d3741661d6d3147cf9c83a68915de35790b3ca42468931ad78da0cf9e363e313a34df9202da87e18eb4ab2fb0ddf9bf7d5074b2428de973786b14157ca62f67f757a905549463cae9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3d37f47845010005fa5a6a1e3547eed738f4e18b20bedb0a1e2ef4aabb62c6619081d8ff34303dfa511eff5823d4f5a25e3a7ff447e05c16a31d6ea1ffddd307	1619422712000000	1620027512000000	1683099512000000	1777707512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	201
\\xe30932baf2021ce155dd83cbb23a206a41bd788c3265ec3029237f7cdfe6ed6049435dee9a67a70643042e86ed01ee8572ebb6413551950f7b89fb6f9b6c5bbd	\\x008000039dfb127050c6be349ffe882e0d5c4796dbbfd36a1bc472fb2c57bae0730c0ebb6290886002aad3ad750b3cfefd1c621adc7f90131693b92ce366ee4aede05d62e29ae7b461f81acb3f1f3ef0373bb41cb2dbbfa2115fd6fa5b293e1107442872746d74125c9896661217914f038f97d2f78ffb77b4910aaef881e125a9743f6f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x0f54accf81eef7db7d332da1ba8567148cb43a7e92823263047860a3e62503f2e615d5130a3d812ba3136592884ca64ff76f7fb2cf0050e3cbd5085d83080e04	1630908212000000	1631513012000000	1694585012000000	1789193012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	202
\\xe3f9bc0f3f395f8215adddbe14e57af7a5f4a066a25f93d9185d948d2d71e4e2234f6e4d21b4ea63a32585ead7d6dd9ca045e010b23cb5a82105f899e38756c0	\\x00800003c25bafee92a4fa6026e7c81a9d300ff8d8560e0fae42b941959e4e1f13fcf9d67f9893819d38e182ca3a54be0ae587b308d8b5f21afc0439f3d07ba547904924fd6d309a824736ee105fe05e777f7b68afa96dbb74414b5037712a54e520d54c07730b40e4cdb2e1202684b3c0002a515949a3696de3f7d28a091374555e8c53010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa69058fd927fd463b5f0deb5fe2f2fde857e84af82bc86da2c4b57c69623d3a538d65596f681028d805ea2ed22267537f02bffc129e286390b8ea23834149409	1641789212000000	1642394012000000	1705466012000000	1800074012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	203
\\xe5752e4f12ae113a705dd88e6ed8fbe61f16dac5160749606884da97463db47316fac0836ae652e01e423db48016c0f6a6c894caa81ce168d19b6f4bdb424953	\\x00800003f77dabb84a6e0a3a98e89da156e8ad24d3f470fad92ea71e553cb9c702ca0a4b1d332d9a1a08afe4a13a9ff1cb6bfc00f1a43ff96684ccda0e010fd4a5900ccec93031062836c62e73790a941496565b1eb910ab610088726d12fe53e301700f24e38558b9ace9e66048760bce4448418c7cf802e0517d323ac8800705f9dd4d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9f55a7aa3af1a336c8b99d8d46a44b45f63609271a627bad0bf03042f8a1ef660dae431e535a9dddb33ed8687dee4022562fab37b114e6209785fa0617792c0b	1638162212000000	1638767012000000	1701839012000000	1796447012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	204
\\xe81d9ac07af09388ce074918c2a4196288cc0cab6106e0c7fbdfa0f15106b40ec32d21d7cdf1154838bc1228b694f655794865149c9ba61d8e7434fcbde5d13b	\\x00800003c3f7755d9db200818202bb3c227f3542dd2b5682347fa28af0528885bb4c28bfc07add2739fb8d6a4394a6006a31076c36cf7233c8dc8c36d9ddf6957520d166e34e62476f9fd65f24ba1c69f77daa91d3dceb385fca451f9b0fdcb9de591da20effd97d48e953fdeda7cb8e2763e38a82ebe1fde3cde8ccb5af97b41ae3229b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x63f60515076c00ea61071896b77c5d3039a67a50f1c0824e4fb4b98c18212cb78d9a6dabc3fea21b219c178407d3fa5bcac9e58a16d0a41880d2b575615e0d03	1638766712000000	1639371512000000	1702443512000000	1797051512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	205
\\xea0133ed264eb9b1ad0869ad21ba87befd8771339d0c065eff2611cc7174e61cedd5f5e039e24008a46a2ea38817c5e2350e00465a314d9b8a5b440d69c06d36	\\x00800003ad15ee89fd7e68e199fb2b39b649d13ac259b8c5d7e48b159754ad1be777cb7c0cd0bbdea18b360435e5760acc948b387bdc5cd2f1754c8df4e559dae0fa7170186bf053604099a8094449e4313749e5e6f00b7ddc43851a5d9997a42542ba9d9114fcddf9df4b078ed45b736f09c7383ebf0719d227f2f02eaf35b5ec2f24d5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x468f9ba8fb07da5c3187675e6fab8a0f8034f8eb3fa3cb837cc83f8e2d33b3025d8edf4cc686121ea86f73e78d223c06fefe3f79515a51890a0a7e871a0fd107	1623654212000000	1624259012000000	1687331012000000	1781939012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	206
\\xec41f985f049a28ef8377f36e836d9cbdb922c8be7583865b3ca412f413b3a2b73ff91b789efd54c5007ba706dffc68854b707b2b3b031c318139c3749080dbd	\\x00800003d731b54e20fd4bbbd5e8775ed703f7520b60a4280926de53df25d5406619182ed3caabb0f6b1f604390a1551bbfc37623422e1fc828e2b7b61dab5009370d5533c9f71489ebc7dbe48ac9ef8118a281109c09b89440b97242765d353d2f09415d28390562186564dc9b4582a4acf6824d7b574cb95f583309152a5cf197f7507010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1127830c3d13c2cf043a600510900be8c02908c2d467a49b2c1e6ca6083f1baab0832b742ba411c79d23c2ecaa22a15b3e908eaa67902c64f4861c7e324c340a	1610959712000000	1611564512000000	1674636512000000	1769244512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	207
\\xf1c132ecdc89f4772adba423ba92c6945a912fa22f8ed626d9941fa1cf35f6ea38b8b8c702022ada5db5b4a4acdd392f5e38d56d27389a2e204d38e086402342	\\x00800003e88a3e21ff2cbb81a99cd36b1685e801bf257974da6699d4db1903de66c553a18c72ccb37801f7337ce77c414d187dd4a5a1f92ad8da9f2fb07db6fab17ff60c7d3abe075ca4cbec98702590aa2ea8236054d5c78f5cc2c80e3ef223c2794762ce059fa0a9bd802c5ce95f8bf95cbc048774a9862f3af0f1d2bf44092810023b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7766e46a74f5a443e0ed0a4b8c8c3a8c105b122cbdfc552f0391c8732a02cedb52c445cbdc9a2239909205200a72ce1d71a78e0fb40006bfccde528a3cee5807	1619422712000000	1620027512000000	1683099512000000	1777707512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	208
\\xf391b426a4103ee4a7c4c709076ee10e55be34806a0868e76bb6d580e4002ba8b757cc4d79ec39fb9e20178e3208d17c9b841e295bbad3d2256da4455593ec16	\\x00800003c01ee7668ab3d3b00f1b2c6f5c76a9a96e519da211241a33d0029b75215c7d7655573b99dc1ab74a5c6a0220a1dd66e472a4ccdef604e7adabb886eb85c26769da85449def56d4b1c1b0753fe9c5bda2c2704bd17e757ca32d6d23aa78278e5600545405f273d52078993cf7d29c88fff25bc38c909f988eab230810e3769787010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xac4e396f902c56810cadde21f5fab6530dc479132fd98e8a5094911da9be658b1d7bd4cb761b13f7453bbfbe0eaa52a201213fbf9fe29adbc23134ccb99c2706	1618213712000000	1618818512000000	1681890512000000	1776498512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	209
\\xf7ed957a16df460cfa9ad27846e5ffe582d511d60661e57de50118d6d33236185f7119cc305959e5509b3eeff39238d10d297750950303cd54c167c602c458d1	\\x00800003d946d085bc5ebef9d5dcb64e9ba5608b85c8782bbe590c3e795a9084086afc5d2298cc64b1ba0593487874e613f7d379698e0b0ebd04f37c0901b6a8272d3102aefaaa9a93284b53cfff0c60324df3a57b4d994f15ab47de543ab1aea1509867a0858f52e6561649a24b0455800c4a4bad80050ce0f6d83ef5ba268e29933baf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3cb7cb882536e28e25358a77263a0d2eec80cc8d9b613bbe365b2b3402774709390da87c6f38d047a4c2bcd7dacea42d223326eb98ea354895099eada45f5605	1631512712000000	1632117512000000	1695189512000000	1789797512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	210
\\xf9558623817b5791a3d149a36e901f6b97de69362f9d6cef3580890d10e75ccabe54b521e520b5f1963bad28b1c8cbdb3f80a68764d22baef3b6cde84a5527d3	\\x00800003aa0ad8f5f97f2db532372f86eb73e29023a3bc6fa1edfb58bc653fc01519d6506cea73617a936b5b728f90f2365249b41947a7e7cd1c709febd08f63b342f1954f484cc4f5d0834defa8a3213e0534470144c676a18653d2369fe82b5cfd52f8682a81cd955f2cac5bf9f087437d0913951965f5853fd92dcfbc5b172c03c089010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd089ff3fccc12b81f8d187d6a7b09311a957a5d32183855fba1802a6a1f31997c80cdac7237e3516b55501f1c389753dc5031368db3902a8495968256b4cb40d	1618818212000000	1619423012000000	1682495012000000	1777103012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	211
\\xfda1e5461163a7645f571ccac649c9d3c973e25decfa6217246d9f92fcbc4b6b10e7aa5e2a766d09b417971880e88c443f4c1bdd5695bae4a8f02b62357557e8	\\x00800003aa062701f901322898d33e88c150c55761ffd39e7ccefc9c4827bf87e56e799d5d32846cec5a29ee89b8a2c45e17d59cb40a3a3a6d536b0ec29dbffbc3088361c600586b0a81c647a3e290d910d7c2d3814c7c10834380d3197f79ba1553cdc965377582203e04b0e7e3a262926ffca65350572837725d4f33e376d5a74bcdd1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x66f789741f082e8d2d69686e6f2557f8da64c625311270b9d4568c4021548569da567c559280a5e6c0e85af3c4d89a7d529e792e4ddd69fd7879e0b7a1d65703	1621236212000000	1621841012000000	1684913012000000	1779521012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	212
\\xfee9625e7daac98dfea9c5f2b9fd29e3dc00ce057d8ec81972174de020d17ce43f1b0e9620873d1c2d20548eb3b8ff5bd3ef97c532f7bef800d2a68f6d2e6337	\\x00800003bb91a2f87f46fd61727f2a1f1ffd3811cacefef0f9621ac4e3ac29603aa8856b44e9e15c203852cbbdde144628b3e798290e5ef1c7442c5544fbf6d0c2e3afeb6e2a498eae7b87702e72008d66422b729254c35fdba6bfee801d8037bae63e2f5be87ec6d917bd43e2b8ffa562523138b9d4447c22fd4979d7be04bcbb1fc09b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcaf7b85a89f85edbe88a1c4e01fe592ec0b09264e1748b611056cee69ad6a81f5e64c798fd3bdcd9084b417de1be6476e95896c3bc4dfa8b36213d82b77dc106	1615191212000000	1615796012000000	1678868012000000	1773476012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	213
\\xfec1a975b77300c1acb68e10c3aa0728e1344beaf908aa1c7e242c1325347ed65da0f7202592f77d135052221936972c9023022424039b41280e42fcc5f20b2f	\\x00800003a3b472fb5773dff7cfe8c87242f34e4e9bfa880a57e6ad3d04d381af17e573f518bbc8996e03f0e8121ebb72f203ed2086b2c709fe0c56c47334b133c4d675733b3a7497b9f6cf8bf47c55389d4f3aa04aaed4054fab5bfaa4866781b1990891ed57d4482ef7f5e5edee7ad3dccc56ddab107354c8e6de767e2c4c6b3a1fcf09010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7ba014a7e6a74d69bdce66ccb2870cb77211ea9568bde891c161c4eb4100265ff99e88b796144240d355ae8c2deeefccb0d56d7b8b4f6dec23280f8a3382d007	1641184712000000	1641789512000000	1704861512000000	1799469512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	214
\\x02ee9547134298a15b67fec862dfb229bec7204a3d7a191049f40d368879a888528a661962b0fd8e967062d00a55be8807945ec797083cf48cf9a0e7ca5830e5	\\x00800003f0ed125102ff061e2dbe8e499a8684ab14c65d1b1660be7b2b1424e9aadbdafe9b4be1553ca6e3d2c3416a78a679c15bb58741a677710357369caa7774ed9dfabddeffa2b9be39c041de92cc06e344dd87d552b89973bfb46ec8d04f5cc207c13e2cfe79119f84cbfa68bed6ceb8887311bbbb721f8a8228fd9f993d58f8b239010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9278645a17babe6a3a17db72f9ccd2d73e7e04b843964a90666557a018573dfd30d5958be6ca777cb55e2c8d306dec510eb8a37a2280a8b2e2f8371ae40e650f	1637557712000000	1638162512000000	1701234512000000	1795842512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	215
\\x0642c43c7522cd0799251e8701bf995a47aa5e78f785d06cabd980c32997eba79f5257fa1c8a7a56a6e7c788caca4ef5328e1a095e716ef81eb8cf2ae4e6a132	\\x00800003eb226059df01fa0060175167da9df518de73fd395974fc2e6f12852e45825930f93263a7a2ad2e4ef7b4c6cc0158173ebcb4b89d47ba0d73d1c622c7d26ba0d2ab1e98862d2a0a68fc40b7bb458de1a3d8c2093ac9f978e679c9e4ccc87455bb08db2412d5814ca9f18f8dc7bd0005c51a91bcca8373745bf63646efd433825f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x846ce654c597d21454585f203c54c862ed7cee0981649929111b29c981bb4c575d9918ed9e531da00d3dd046f4d18debaa478fdd47e713fcddc7b6a298de2e00	1610355212000000	1610960012000000	1674032012000000	1768640012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	216
\\x0716a914826971a286c70dda1a43e5fb83e9125ec1f05b54ffb2cd538ccdd37f1dba1c94392c1644bf63c3dac6b7ab112f4c14126a8cf9f11d0110474dd3e5ac	\\x00800003ad68cd70f2db3cdebef75da1069a04c81a9b1b30a6cc0251267da463f997fdfdc0edaf8258afc7ad63c44f455cdf2a52442be47e435553725cec4bf24ffc3330d8525b5adf4165ae2778f2c77eac16c09b869b9496b6d8ea76b894f3bce0519e3ddf364e22e4845ade6cc4f1cb7df5fac8d9884ab3022f9588c68b2da6d0e943010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe4316b76fb043685a1b8a2fd0d41009082b9ac84bdffd62d7fc8a5c67938ec6905420effd10b1f346c50b5b49859eee87c38713970ecfd062196c26740a8fd03	1612168712000000	1612773512000000	1675845512000000	1770453512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	217
\\x0e92b568f6b2be331f5ef071eda764c5878194d8cdc5325f0b60153c6afe14547a1a1a04ce59b0e91a9fef06e182838b3f0b28bf82e83be105bd9445466a8faf	\\x00800003a1ad06a3ff97b8047961603a10074d1fe86644a3cd33c33fcece007f75546f7114f15dc53b4cc0fbd4f5d98e33517cf26e6111d73d12ca8ccf3b0d18cad97aef9d8c1d6d5c513772c58a0e453d624f21a1bece816aae055fe9daa80a8a5921eccf20d83932d25fe36dd813a9ea12430febfef6ed3948756698d4e0e6a3436acd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf7a9697714a001a8acbd20162502c638f68e5990d9cd2ec4efb4c9204dd948172e57ee79133a92e86958627634e6abbffd10be473cab461dfa33bc09aea4c60a	1639371212000000	1639976012000000	1703048012000000	1797656012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	218
\\x0eeac7c92c0a028f4d1c6ea69cdf273790e76afedc2f91d302d376c7c9cdb78164e8051baff91efb58182268b70d714f9362b290b40381a2d6d268e9146ab0d3	\\x00800003cfe3fa006d274937c0d4d0423599da52f93fe1723d935fa63f987d190035c6ddfad479616da9d190011b9c6d1a0c11c540817a637795cc12832d9e435f1f5ca4dbff0dfc5154ca6de80c272954db1213e7f69fc21c2933b60981142100573c4aada9c51acdf8670cfdfbadb412434be42aa0c9ca7d7381efe617ce382072a79b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7f4166449b6c3156a321cba179ec967a5943cee87557f1c433f0ca06fc73ca3872e4483169f4da43f1eba51d0f52f32c3a4459b184f964639bca177eae94db00	1613377712000000	1613982512000000	1677054512000000	1771662512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	219
\\x1572eec8712eb9271d1fc067441603b37c70747bd843339ed3300f6688a26bc1f1b7aaa5a704dca76e4a677d03f5419e844b219d9da8e8977d5d7e8a4c732067	\\x00800003ca6052d20fdc1047b6aa9d6f5e194c1dfd137b2db9ea086abcdecbcbc667407183f044bcad2e10c22addbe3c4a4d36352d525fc4e1643a0039f0e6763f75bb954672c2ccd44d0e6689b10ac1913e6d70e1a648890d296817963d2e63800e51a8329a5f788eec0b8221ef2fb56832013e96ac8cb35393948d696f5ad9c8a5a69b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7bafa1e81ac15d7edf80a8bf07e1a327c0a1ecce5bdaabf8dec61e2447930ea675278cdcfc65016b4521524876bb8377719ef8591cf6041b0fcc54413151e606	1629094712000000	1629699512000000	1692771512000000	1787379512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	220
\\x1512949ce274774624cf80eba690f9861bfdd919d5979b620ef1bded9b5e69b82794f700b3fb616bb9a83e68868f11a23862f0aa2bc13ffc7ac3006aa21e9907	\\x00800003a4ddfe200f5845ea45ad66c0652257b0c6ffa17bd59c5493beb56d11160181847677d237dd98a4f898f5c0e0966328d3637da02aab25fa9dcd479a18366dd8d6dc65459b6203345fadb8c1a99ce0d2db099c389421042e8b0f1f4b6bc66e6d0932064d5718b04a0c04dc0d00e24a208f8f46fcf61626e70e458999a1dfa46977010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5b95d5b3a0b8cca86a601b497cfa4e74a7762e04b8ee1585d1244cae9de4b794e64c73f90867ea3d790a89aff07cac24ab7ed1838b00797fbc0eaf71c49a6809	1617004712000000	1617609512000000	1680681512000000	1775289512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	221
\\x1ffa9349794cd2c88971e4751bfb8dd29a3cd2e5b745f4e547a5c2826ef3b418138c5e95bc9770d480f8cbf91223cb39e0d6d5ba30d9242f884f7d46af069cd7	\\x00800003bad5618ec1f31f5a58a95185542f50d5be716fc6b993ff99a1075169edaa6625fedbc6aecbd30847320914216a6a0f90478da2b8eb2c8ebbd5d5a172f94cc9ca6bde9f4c6697885f9689f8b0eba3ec4e5b7ca3ab8c2c8fe2b5668e42e4602a4bc2393bfc452646a9f22b78c2e4ee079b99b6ff6a15033d515ddb6c88e5a0a4ed010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x41d275e5e8016384005ec7d7843507f9827ca2892d7657ea1758e263ac40825b67e53c00381f11630e9670627cfa4428b05c596a16f5e7b34c09296698952502	1627281212000000	1627886012000000	1690958012000000	1785566012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	222
\\x2042cfc2935041c76e00b9112dc79f970ff1813aabc717e839bc81e41203d040957699262acf99dbc9011e8545104d58d1fc96eb6fc00aef96f2b620224d0411	\\x00800003c9433ce4eb3ec415f8dcd1f5dc440d19f26358f65ec96a06fa31d72413b5c1b826d4fffed7cb442e6f4803338e12417c001c669385985634c3c6fc6c40925e4375f3d9a9851377f090579b1d8a59be27447deb937431b457b054ca40ca04fee21fb623cdeda50470e91580d878c3287c209f52d9def131f5a9a63219af988e25010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x542bca6679937bdc8fc6a546ce3c2e2defd0a54e44a3b7d8c58ae017efbf474fd6c5b4638499a8452007bcaf15974ebcddce2202a501277ca31ad256f2624205	1630908212000000	1631513012000000	1694585012000000	1789193012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	223
\\x2132bf79c58e464b79e928e2e74a4053397afb1903b0599c6d4ccd2be8fb0d78d04cfe496534259687bab891a1408689c81241b2b1aaa1ec1966e56c06fa66b4	\\x00800003af005ee6b9283101056530dd91c249541d1d34fdd90e4c3fe7de71e400aa8c9bb16402583a9d7252e76750603cef2b70b8964c7d0025384568c1382d548d5b1e45a10768ab92fdabfafc4fba92a48c10a4f00ee3e8ef351c1933bc3fab764b132e792a2a5a7e517b7950cd3035fcef347a0f2c93c7e9333e08e2a8df3524b227010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xda2b60065516be39ab911a7ef99fcf19e4aca430001f14f77a764def04fbb3224e8afd22c7a493324aef1589abdd59578d3391ec30ac4fffe6a462d920da6608	1638766712000000	1639371512000000	1702443512000000	1797051512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	224
\\x222e3095b694560a798ba39d5cf299e4f45407b717cd5b82ae70a5eb7c8547ee350ad17ed39dd11919807fa7f0e1d8041e92516147f0f759c0f2d8f1a181d373	\\x00800003bf2744cd2e464b25b3cbf03027540dbfed5758d456fb387df213fd191cf50a02167a83a80a8c0e32e204f5688d823fc1f675e0735065ae12343b30244cfb955b6c09134815c2b2eda56a95b9d972bb390daf4f5639935942176fbbb9ae6ffcf02a388cfc5d678207d145bf1be1e1e2c17175c4276553802751337cd3faa60585010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x97f73e08ddda0f449e37ac2656d3892f008e33383c3850545c11117ccf4e7cf914523d9ff51d17c158e9e7fa47255c8ddedb3c5f2af204c0a0e06ebd2f2a4b08	1620027212000000	1620632012000000	1683704012000000	1778312012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	225
\\x26d6a8ce021aa66b05913173591ee6e1f85fb5e8f8da6e6ceedac5b7df2e00c88b5bceb88dc4b28a89823dca6afaecbd0011a6e514e650542be306cf7b7d71f1	\\x00800003de335b262c935989cc01c6f3b92ea888276dec8cfb397cc6e57401fc32e58a39fb57833d880557bb6dae4c2f8590c264e0ac44c4841d502635def19631a57d782c67c94f46dad91123445ac6d7a566c00f07aeda7463a6baa8a10080180b7fc2858aaa3bf584069e0e53a5c035cba9b86ac52b0bb0c268bdc87b9d725b92d5d1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb54d20ccb6d77b02fa2f486f3118331a4046c1c7f11cd9b7cc273b1e5fa1b8f03c7c3c88d5d2d2a047c71981d98ea11a772546a819b2530d47f1c3eed51a7100	1617609212000000	1618214012000000	1681286012000000	1775894012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	226
\\x26fafdb49b4898409bbcee21cb854977adc301be26ba421fa5013212b872f95af3be799c1195aa91d1b52f2180774507514c4a4f74f2e350dda95e6303e8a180	\\x00800003bed2ecec6cca477309011990205ffd1583f3d28f89fb64b49ad027465e90841cae31e66d9757d6c7ff754422666b9119c81f0c38a6a731dae30fc0b0fbb58dda333d0b9bdb8947cd2078faed0db5c19f3b4a5fa3968422091ed1bd9d7eb01fcc938afec4fc68be564980b25471c64a434e77e035c6f874b3e1e89c80386c5b5f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb21c5ed4527f41e923606249cd8e8d83300873f01b3d682782012014504bf38091e0673ae37eff335bf2cf93f47658a43f0f5451d780183d4ff825e4e0eebb00	1632721712000000	1633326512000000	1696398512000000	1791006512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	227
\\x27d22c10e31cbf00071c2619005af0920f43989f6ab5cba9c349fdea92f587bb4938f31b1362624319780f99bcfb3e5d14cad404499a0e01185eb37e3df8d522	\\x00800003c293025444a97bf45838cbd6eebf00e89e5907110a2e851775c3513ee2730f03f8814c397c20fa8b906474838c52435d5f81c96b9db6aa65ae6a8ba8aa9168ca68fa619256970c72c402710e54cfc1b614452f25a02b29150d00fcdb6dc4f2a5794f40837dbc2ca411d51ba1cae6675e4008aae870df9733de5999ece6c37ceb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdda0840bc438ea20c4b2dae7e572833d678bf8c177ca5595fd69b008a7de53fb2b7bc3a93648eecaef137d60ea9e707af7ff198d9b03308634faf49b42486c06	1637557712000000	1638162512000000	1701234512000000	1795842512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	228
\\x2c52dfc9ee2339f971ce228a26f92264669e9b2a5ef779c8744c0926aaea13e749e54158a8d0ba90455042bc6e4e29f05260cdbf60958b2302c5ed0c7e5a4769	\\x00800003cc6261b803a67cb1fde1434d2342e5baa8930c2ff5f83ffc944125bc1565964a7bdcd3e04a55917f79780aca1e6f12ff9b22f21c72668067059f1712513148c8944f19583803b2c15e63ab9c901fa9ad348177f475f8bf2401d9da383d7d991f47d8e89f84b5500ac7b465f38854f2c3bef1e340157cf138336ed7deecd44d1d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x90007c04f41092e3eba938274ede86476e0257fb95ec33f722bf3954a491bb4eaefb415f6785759787a9c4f0ab607e1afe5c7e4ce84be0d03328fdb9059c960f	1620027212000000	1620632012000000	1683704012000000	1778312012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	229
\\x2eb296950e0ea47a3b15893e7d9a6138a8bb8e32923da54e933f360f316ba4950f73db2ce42e205de0daafee0168444dad99b1dc66c2e62af3b59a8318662a18	\\x00800003c2b00e05c0ff748eed18230edbffccc2d44a9806e77431309b67db3bcc27749196b069142dc1673e60218ba8899aac2421707e4e35ef9ee1f76bd6d35af1c248d4107d4f80100a4938a3724c73c7de65e04bc4ffa5acd048210b15e7729698b27ee533a4fd103953270751690e3b1182cbabcd255e54f2bb769d5ec216a34c8d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xecfc0083a447df1fb1e4de105ef54833bd3c2ce4161992e6623f28b619e50556f774d36577b6fab4474d80bbd298f53bf68c02fa4176c37fae879c01ad25f30e	1622445212000000	1623050012000000	1686122012000000	1780730012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	230
\\x2fdac0658c141d4f82f2c1b2fc8dfebdad9c05a1f84cc4e0bdba259ca3913f0fb5b5320ec9b16b06a02fbd020527eae4c7d9165fe9c72477d45e520cac6de71c	\\x00800003ab21bb66a5fc1bf64032698056c1f3b9394dab1ec23c4597de79f44c560df2feb00cc18510e7c7204a6ec1a181ff0edc3d4855dfea4bd44f1cb1dc857302969662a46cc055234b9701156c2ab2264ba52671bc79e2f49084b93e3a9060f0be9ab1ebf9d892531f2d8e9a0c73041a6903484f08b2b8fb802c4285793937fbc93f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbc5c19388d302b2943dd5c6e053a3c64b47161954d326c723f09d991fad261a9c72d23ecfa62eb698a937b5cc386419fc1e646c312c1b347d0b16a5a142c9004	1621236212000000	1621841012000000	1684913012000000	1779521012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	231
\\x34ba0c444b4d970cd484f43d899c53f8818813e22b4914d08ebe27a90f29f6aa88bf5247c1e9a93c63c848fe747ab67544a51f7d7e54fa004e0b46e053066960	\\x00800003db71ff4d52bc5e2843f640c9e5998b27d347e3cdfdbafd02266cb668806e5532a45e0ed94d98ca67d525004fc5d171853bd2852464198e77587346b49317d2b48113252a0289d7686152b5fdb881039e4cada1b60d2658ed472b9ed5d48522d26e735cfecd3387b5d4c168fda83c72f16febd36d491386cfea26ba2185c93319010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x38768a935985b5f26e2e2e8ef069873c1616e70eaa8378e3bf59e740b58d5196ff974ea451f3508ea0eea896c7f4ea51bed21c8deb7e72744bfe1f7d9966f900	1613982212000000	1614587012000000	1677659012000000	1772267012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	232
\\x35124f53ea5133ebd0dd6cd5b3c20f725a4fa2354dd0ae47e030c2e4b44f9670ed3cbfc34fa84bb4c1deae38a3fcfed0db3cfe5c24298b3fea1f8b04ec228b8f	\\x00800003a6adb3de7e52c21650cdefb86bcf28c638f5aafa7c1ce88191072842359395e95557a3a6152e6fd953ec0d3cd69eb09aecf7fdd55b091a57d2951d329104fec711346abe6c36d64c4d2922d9f1743909633315dbad6f816579f2add98e2f7087f281582527423d9ae370ab22d6a7f6d74f98af66b2bd9dd0aad667c7d6e482db010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x06e35be184691da4b98c7f61a2d9a68b8ba483484f6d54740ab0fa477a80d3928a6045e25e8398ebe4b61f7266e827e438b4e7752bf3128f9229c545f1565f0f	1623049712000000	1623654512000000	1686726512000000	1781334512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	233
\\x3692ee916b073a1a64979812b41a74750c09a9fc768d63e25e6b74481a1826d332c731ca43560f08b86486ad848bb09d8a8ae44e3f3a209b387472c578ee33e9	\\x00800003d280da2aedd01464d5b5c0fdcee43ffa328d0ea68d0cb94ae2433296b96644e2edf34badc444cea65f46b6629a1edec2718c9e42de92580191764b7f9ca06aaf2deefdc1e4a7920c0dc10b7a72495e9977b0debd605d630e5760e4ff4f774f3fc5e52e19f0eb1563c6f9a8c2292f78b69b22805ad5ec91c29b4613f17b915de5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3b96b5e06d034f5f30275088e67f2a6e38b24c825735102f9dedcc5b433b723900dd6736d693d62fb4c31908e2dd0e50fa2abdccb385f6965147ef4c68877a05	1614586712000000	1615191512000000	1678263512000000	1772871512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	234
\\x37eeb2dd87dfcdedf2910a92687ece2427e7fc3702e8bf549af2923bf23ba5358aec210c975d8b323ee7141e1bce6efac43334a170381948e050a7b5a54bebff	\\x00800003df03fe3ed745787e8386f9c36996e1e7ce7a09f49f23b68832e44a9f26f50405f57bf60e6f2043ac24f65390fc1888df061636fa4b155a0bdfc41a89adee79d608ccbdc467e8f1035405b1e8b03d2a75e115927d877e344e2a3b586395f25b50978a02aa6eb00029f5a0f2d6be3c5a926f2f631ffe463d4edf1c18bd3d94efdd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2d3ece108d0f211a5d0d1fd79f184d05fd50fbd7af7ef122da689d3d5036262c49d54cb6435c64caaa94698a66b9a027a8c41df9229c20aa90ebdc8be22ac00b	1627885712000000	1628490512000000	1691562512000000	1786170512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	235
\\x3d528a3acbce8d2dd6e8b20d8022dc510b3acc9cfc08beceb37e270e89dcf14625efc8b2d4680a899b22c31b23e9914a96c785c2213d0eb3272066980bc53d87	\\x00800003d28bf294fe45e05774435dc0d58fd8949565b239cc36a4a12563b7274e0621f25bd1fe233ecc8c5990a8003d91e31f4328932c53c6d20a7b063a50756ede9f18b3b5c792b5347df6e2828132d1d92e6f7deb4af764875c207717efccc864a2a47c530bd0892a39bf03534e12ea0649be0a6800dd994519084e5543789558257f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x59365796ac13e764ed8809eb6d2ce63fbfdca129045dd5f0191ac08b4b61f83800989faaf58c0039c12826cc79e452f243f7dff9e6286412660bad3d2aeb1c0d	1628490212000000	1629095012000000	1692167012000000	1786775012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	236
\\x45be832592e2a1b9f12b04fe64048518e418c7cf025cdb8916fe68596aea7ba12fb695f16dc48ebfc651c6342f34da7bb3221be8ce4914e6e4cc166703447743	\\x00800003f5d46357fd2a65abd2f52ca4e68cdf847237e711eee1bd25633b17c09c9bac09fdb376bc1286f7922d192c16219623565da30191e52a6eb4194eed3ee87732550dbf9b45cc2da53400011025e0cc84768658ddce290c28a26b8eb06712be569ac753b7ecebf97d57569051b324999743ff4804508f1bee1183b6a11ce37e4d83010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdd242d6bcd3ea5b92e92845be4ccc19c6bdfb317443d2336f5a69ebbac1b2477661bbe49b9a90533e9b0eeb943df2f0072c67bcec6726ef62e3c04e7e373020e	1612773212000000	1613378012000000	1676450012000000	1771058012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	237
\\x4ab6cf9215a952973cfaaa2d4cb555bd4575cc04db70aeb564cc55fcb41f87ebd8102e18d80ee3f901d20c14e3a759e193a99fe3eb8b7c0ef07287fcf8303740	\\x0080000394298e960f8e6ae629f136c43527551085be3e6ce3e3e71b32cd8c219aff6a38025c63ac63f6cd8f5323e68a6ccd34639efd9422375353d03c2cbbdd605720f5287bc2c5e6fbcf3beea75566c0f01f471bbba32ee1e1071c1b6979f82aa67bedbb840c90b0c6d2702669e11c1176acc1f5923edbaf8df909b5b4b56c47c9a22f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x034fa0bf78a74ae8565753260a19606ff5b33ee3c5861657f66c375fa3771b600373cb2dd1d612467cfc53f9bcf7f54d264db9aedfb8d902b358473bdd609b06	1635139712000000	1635744512000000	1698816512000000	1793424512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	238
\\x4da6e9ede48ddc49f7ec3ef02a4bf1ac6a0c5828104d3137081c621bda54a87169641347cd693ec27816512c565437a90572fe9ce840058d3c8e09a3948c3dfc	\\x00800003bf2441b69088adb7ba0572c376be4192c2d528c0e299fe5ded0f6c89f775a5259bd976cf97e7e6a74d3d2fff839a62ae5d06f9503bbdfe81bc557e764dc00c4567f09f8828f210636a280fcff887360db3c9ea7834f84ddff7a0bd2bacb461761168738f142b752b519ef9b14b5370bf0fab47b001fce92f986ff94e5d439bc3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xff005c00fed82f32dd34d7aea8bd4eb9bb283fade9c265a8cf72f5dc734ce1bc790fad0ee85cd5bfd4cb63c59f734e95d54c08127d03aab10f77c1788af6a30c	1630908212000000	1631513012000000	1694585012000000	1789193012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	239
\\x4e2a831db6c52b955705cf2fec9f0c21d33f8593e59f6a9d05fa5cb42598b783dd58bda90684f7358170b01d9c97db5751718e377a0a35eabb98f7ee1bc87a8c	\\x00800003ce03e9e02dfaa5633388c2561f501ee5aa29751e6f271625f2f0a5a446b46b4df2daba3dd1128f02d2402cbe0bc4145d2f4dc655d2b01af6c2e1c0c4c626fb6f33029aec61164a124d50d840144c90e314ed82095d0b4d9a1695b8bb07cf70bedf23e0049f212cee1154d8f414600eaa33e39ebc84fb4a6e1fdb820180707277010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3533e81ea18bdc80de5c1c95452561e77750047887a218627dc3e8d66abb783372b454b17ec26d789feef356bebb0c89e90310cabbd22c4f17e764f0a733af03	1635744212000000	1636349012000000	1699421012000000	1794029012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	240
\\x50060189f5bee1efd4993d78adf3ce433d3db8e1ddd2ce4ed2be598c4e0945f2e9a9204cb7cef80eef452e29b44865ce07b64d1b02893da00eec27cf3edbe680	\\x00800003eae4f5ddca73763d78c4fda2e7dcfec14b85616554782e6f2ffe6cc8ff3d43ee9457ce86370d1cf3e7b8443e53cb2b69fcde0c02576f6eef5ad585800c9e4b3135f385e387c421e337dee9d13d4d4d48a24bce64f156b5f14e29aacd214b3ad8c000d9e9a441ae3a914bf879c10c15f87c7c8de730f6266e66b88f46d0b163f5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbf15294f8620b3e298db38628a33cc811043de910cdb31c3b4510a49e1a0227653e870037bcffecd74ab143b1d6a92852f60e0215809e14055b8699ceefb9f00	1627885712000000	1628490512000000	1691562512000000	1786170512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	241
\\x50624d4c2cb5dfc1bb27aee9d3816d733d5ad0221bd18b980ddadf8195a76b72f4d2af5f607708475e9f12333bb8e3eb5b7d84511429f8c89aaee16ddf57906e	\\x00800003d0bc666290d7b5dabb25ab0dada0a27c1e2a2c53cd2649d1aeeadb991b93728fe5417bf0dac7a65bc7d7a3a887fcc1fe6a8ffb29967de9ff3618f4f80526544b84ff759ecddf8d5290a444315537111f8b422ae4d8022a5316506762b4362d9e0f965922a37b469eb62977915219c8e462adae214bcad3e8b82beae3bbf0084b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcdaa6c955555b9f9a54ca2c7a4ce2a7ecd76ed94ff967b374ecc9e3de21954fafba01354842db679a790eebc13e6a9076d20a1bb8e5fb65b3a5217c924b2e203	1626676712000000	1627281512000000	1690353512000000	1784961512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	242
\\x5092cb17d1de7f30506c989ebaff7ce3685fec82abbfe2d06162020978311c6a7f60a82601c12e58453ebefc53051cf31bd2b80c3244f449263163fcabce35ef	\\x00800003a0f916c1b6f612a9e2742edc8692400571a0bf7fd9dfa19461e8190bb9129a20c3b7df6417024fdd83fd6e04e8942a5ba31e82f7167552d3ad44e1c355242286f3776ab79edd72e390355a9af0adc8e96ab5df3721fa520223826e8b903d32077c7b912275ff8882da1e8fbc29a8a6da3c26f6ff893e3ef8cb39553ec93edee9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbdfd245cc289fa0b0664b31da36783ec4ddc525ab7b882cfa85ff228d80ea61fba0b5c21695595d4797814a60c0e2c936f567387f31e4a7cfe60022ff3e2110d	1624863212000000	1625468012000000	1688540012000000	1783148012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	243
\\x520ed6ada79ac5e6636ef19f44c192d73b51ebec43d360a70524a75f9186d0147ca74728890df28ab81e209da4113a4624faddf57eb739177a8b5fc035b5ecd8	\\x00800003c1ad2c96016ecd76010924e968e8e30c27dbed6d5dffc3a755d36ac4f5300f8d6b7c4e68fc0eede79f089fa357ad8cdab33c83ec5536da0260ddf04063a8548ae79ad0984ff08a9463e21c7fbe2fb575cceb0f8f65231f5ba27a96179b4c942d045d107bd8beb7b6e6da27f3786ebb0851d17a57a3bf066bbe82f56e74f3b92f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa6076dee928239da87ad5762f27647837c0d2495d31a188d96240643841b5d181aa408e5bb22e713b60f8e8f8b1335c94c2bc3db97adb5911819ce8806d94900	1620631712000000	1621236512000000	1684308512000000	1778916512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	244
\\x53dee52d3a90a4d9283e3e627f6b869d64bee9d292bf428ca65eda4967766b9e15e507929f96a438d28f929d5e77bca9e3ecf60fe0506ea637c3d0177f785fb0	\\x00800003a2f1cbd71d3b2fa877d1f8749150929567a23a507d7227f2a4e942adb7373273abb7a43c87a7d8216c16e0225b41b2fd8bdd8d55e9e443be7534366b2d50c0f2ea1a938c46860fd01f23b6f3469698167d002e24c8266eaeb10664ba650b05972dff1371187ed48ce9fb591818393c5aab606cc73b3a396cac3d2d41059747a9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7e1b44c4e55c0634dac8cafdd02e5717152a0ceff4c51893fab043d3e060684ee4f95c74760339c4dd85ebd917eaa91bc75e7ac2efb542fb1c66ee2b78720607	1636348712000000	1636953512000000	1700025512000000	1794633512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	245
\\x55565d65c5e2d0b5f7f980bec8069d2b7a7a9cbf1bf5da6227a5443bdd38cf41a285b1909405bcf91a2f8add399e6de18950c51198272bee6ea0b2ad1703304d	\\x00800003b947763d8af76677b7f81fc151bb78cc8731fdb10511c5e834f4c5d96ba58da296281ea1271a75c923b1aa03150fbd2b432ceb51c4b4519171a180ab916431e64e6a20d5f6c688edc2dc7b9bbe4aacff1f900fb9e8b2df9a3b75e9b0b4f64c2dc4c19c80bbcc8505a4ed64ea1de4b9859db18f9a2ea12ad028f5b978a53b3d93010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc2d48a24e1b6212311e222f50910dbc8fc96808a1d30c73ab6eada03aff825025541a211dad321616ce480a4b19994508cde16a3008f7b45b17fb00450db0809	1626676712000000	1627281512000000	1690353512000000	1784961512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	246
\\x56666073e4fcb210b8ba1396c10703d210d03e38ee1c56a86a1e5bdbdaa8708e52bacb62a4a669d5a46c5d70beebb6cc76076c93e8c521bae3bf87ccfd6d335d	\\x008000039809c068d385fa48b414ffefd9aa74e75db8222b4a364117fbcf592f472e8638262d0d239da4a9a20a4bbdf1dfcb11e72290e911a62ded436a43e2d261a5806b81484653f0fa958025729e43416d2eb8565b5973badec0e6ab818f322a98dead1ddee07f070a11f34a807895da243135f16aa2b49644a62183ee521a5b4fe903010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x0f40152b8e1cf401fda32a38005e5c66d0ab9d497711f07b9abb4c5c7268014b47326207eb2d8a7282c432845870a954360bdcdb772fd97ebf84eacd48494306	1630303712000000	1630908512000000	1693980512000000	1788588512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	247
\\x584235d5d59a7c8cffc59bf10f0c7d78c1bd03db678b0fb685d2715631454f242f443816dee044414955371c11bc792d327ddf5e5134235910361e80cd72a49a	\\x00800003c72f9ef16f828134f8ae43d1e5485256cd691767f49e4f9f01c30fc5fa900f9155ba71557decca40da7374b1c12ffb4681d3588778542865b511769adef5afdf7ac4eddeb116ee8f069a369f6e9fada9402a4b841d2a407973f074514616e67d79770088fd6f3c4a1b8ce7d7bced02289b55ed2887747f7801427f8473a9712b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf911dd0a7ee6feaa5ffe065e2a5703db926d3b54f10db6c32c310a719781eb0d52a7b37bef4e1a65aa5e2188f28789a7f89c07436ce7fe80b034ae214bc90106	1632117212000000	1632722012000000	1695794012000000	1790402012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	248
\\x5bdee9b5fdf56a47a2f11bcdb32ba712cd2e77f6ddfcc01b6ce1b40932052c82db68a8c7a06ff33b792d2ce3f51cd41a1811ea8760190a4ab5babbcddeb50427	\\x00800003d4d1304db69b7cbaeab1978293562d8bc5c27c8e29d55ae42384fd6b81a48abec153c5fee061d2f08db9994ed69202adecd8b7944ec0ae27b2883a27c9799c202ea1e8e38c922d7f1abadd970a338a40038e247d639d223e459d500f2825d006d5f8570e27db76f14fedd9becc673658d4e6a38d074a1c5753d60dea9da6c16d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x61f12ada3ba5c37d02446d88ff8d2fab7231cea860e6caadf7b9146043303dcb69332fa409c685c1cae07beab6a854a1f716d33dc3173fff6c9979be04b98b05	1630303712000000	1630908512000000	1693980512000000	1788588512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	249
\\x5d3ee4c1e0a42cbcf8b04c4edbe3289183546c91beb3957a4579de5489b34fb63f516dc2d1b69d032296699dd1cc80980db328ff3eddf8e06ad5511daaadfb48	\\x00800003d827cf970d75a351f26fe71bf73fd3cd9edfd5c868fd8e290f640da02b736fe0d64f89c35ee64eb102aceddb116d64ec84631e4dfa7968d8e80d9ee9cbd4b5ebe6fcef54ec6a9def0acf8c9a6d10b243ff428fb9fa90a75a76b192b6c28289f6d8d133abd309f3b09995c236fb8d8661b5383991fe33a28b205a4f67c5211c5b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbec2d83cbf0077b613b1e3d9fc6fb48c96391ec42ca32a777176a6d49b0e46d98ae4177a0e9338fd7af1c10b2c9c669885114c7798d011ccb5fd7f15eca61e03	1633326212000000	1633931012000000	1697003012000000	1791611012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	250
\\x5e6292bd350afa5226c03d4668c7b3287d3c9c5cd24f0094e54bfe2c0b95a09f0e52990913e585a5334491386008b76556b75cc4fc5060857f37f6ac8239f40e	\\x00800003b5ed1ad7595009537359f4855987d3476e757be4221e7dba203ae6da91dfa2a506944ba567e410214922a2b04f74f93636bf0bc6d22068b295ad0b32a981818bc1e7c5375de7ab8ea4a9d9b34cf922dca822d99f56afd1ed73dd8384c9395b7532efcd75510f4415ca58aed6a6641dc4af3d69aade043382f8be813c8e3c9705010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3c901ec2e1381dccc9e3ff4c5caef2dbc78bd9a17688e51f265fc35a724df171496e66b0cb853872f5f1372032ab8ca8bf7b75528a1ba120c4316ce9ffb4af03	1625467712000000	1626072512000000	1689144512000000	1783752512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	251
\\x5fda1526e146f92d956ba80106309f9a1be6e3b512731cf09937f32c5f3c1bf694621130db7c5e3d3473ad38243d23548afa8226de8aa2774d3aea103da8203a	\\x00800003d585fa4a447e00dfb16f913ec982b91624cfeba043796cb819483d6087c2928f65dec93c10e367cc365d27e07584ce73fc42308971a3096f5debf7017992d812b62b5e7b094ab7e3951f07f143b7b2e3e8048ddc46a588b4ff9bbdef9fe59523a2c96926370bdf096d589f987ae88cf3bd95ea803ceae723c24a00bb655ca0ef010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xaa23a949a320d117debb82c084ffc7b3119bf0434a94d6d06b60212ec5ca9302a8c35d209de377bc2cf5a81a909780848dfbd38f2f24e53355145d24a253b10c	1619422712000000	1620027512000000	1683099512000000	1777707512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	252
\\x61a6503b113fe485cffb7c404c68c0fbebba53ead7b14bdf3fbb0a47ea57cc854da2e46163f60012d418579804dc15fda51d061a6ff53b594a628633114baf8e	\\x00800003b5bea7e555f487b727d8fa9eeb16294b3ad0ae40263d4704c6a3b7e6a41e0ab6e26e2f12ce9e4e84ff2fa380db90ed6e7f720e010f9c31d922e146a5c7fd8f3b22da5ba8a4309430b97999dc226ae1fc3863cfc4c3c7193ac9c9dca3176833a43246acf884b24cfe43ea476e961178002d456fd7df0bb83bc8cd3191a9c56537010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6a24131b4ec3135b5feb95932b021f8ed3a337844184465c3280a8648ff23b3bf37bab0111dc04e13fa63919a00f3d5a97e16aca39791c68daeceed34ea69b0a	1637557712000000	1638162512000000	1701234512000000	1795842512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	253
\\x62062986ee68c8df16619ba9cb4f44341536a38b8857937bda709f5d4c04d480affff3f7e3bd10077dd3844db6a50907e6a7682a2fe266fcb862c24c1d1b1d42	\\x00800003c1710a107e279645690d742857453e2643b7c77158fb34da545f0c75ff4bef0e972b6a86d5a7f306ff59c7fe04b90ef6f0742e68c8794b6d06422556268e436c42efa5cfa7ce0dd97e659eac7b016fe6f1c10737dee46495d6c1b4bdd188c7fe08522274f7a15198c15fb57f234492c5e9e8968f1294811447ac7ff7766ac93d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x305d0fc3a2b8e3ade974854b15a3d52c5f9bfcc087567bdf93cdcbb264811cea2441b7206d130677db275af98a55174f98ff4b7670a4b90f9ce0f35cd487500b	1623049712000000	1623654512000000	1686726512000000	1781334512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	254
\\x66b656e8cedd370d1aa75d43fa2b58746d8ea871fe1b5253896d9407ab3c400005c587f42de8da5fc1dbf8f43222507f26468c183d82ebb0d278df82b847ea2b	\\x00800003f18aed9b4c584a0e7f3a629b80534792ec775a69b599bcd78d3ebb9fd55dedf94fc49d3dd09f4ac831fc286b287d90b388b64c6defc6757a6c8c8bd5e15e3d3ffbdc08e286041cf175d76240fe2755be348258a28f17c8a9cedffad0f6679f7ab41eefd08fcb7719bc5f27897ecd8a926e84f68b7d0600aadeb6fa55d8c394eb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x84a39548817e31edb1bc98ea001e00209e4071b9be11302dc320064d6f73eb51a56107b886864ad7f57a0b0c31cd84c1831237df05b7907204e03a533f3e3f02	1625467712000000	1626072512000000	1689144512000000	1783752512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	255
\\x68c27128e00fbd6bad4bf78e7ced3587384aba3c647e9ffda556c970948fad2b8fed5b6bb4632a2deee14aafda2a2e379024037c116e9947d0d1ebac18e3aaec	\\x00800003bdd67586b225b659e7d310d5669dbd47ac5883dca19ed6265add8a4c45bfa8b6bab9ed448b1398a2331f8995dfe5a5555a0bec1d68427681ad3e3b71a965d68aa115a9c2deaacb087b6aa7ba3c4cd6e42336c741c4f43f54fdd9a99addfaa616afa894b9e351509bbc86669c319da581e74a0cd0e38ca81e8ab2de4a318aba35010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5d554a1fbde71e207756a3d95caa9003f9299dcabef7b4f14197784023c631dc6a5bdc7c79f26ab3ab82ad4c7512423e30c7f15ab2f2ac60e30220638f623e02	1612773212000000	1613378012000000	1676450012000000	1771058012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	256
\\x69428a63cb48a2550db4ab41d9f89c41dc94d0ce7471f0e7d3fdc01ee95c2aa2937f8db4450ab1d9dc61a4eda0e0df6780bb235dabbd0cbc178479b578a4de19	\\x00800003b990fb95859fdc077d47c3f795223f9799a732c7cfa078df10d5e5d20c4ed90a08ccc6c5d6f9b5a1cd08ce2fdc36f103c16ea160a615f9608c045cf838b018b379654055069b19a2974b1a4f75914f95ec5ca0b31f45ebb89088e3700184070e60ff22f6397635d63fa8af95313399fe09df394cbeed03909952cdccb7e2529d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd3f019231241cbb2a8a285d372e3d1bec616f22fd109e2b5cc5b45ef71208f9882f0d8c96ab56fe0dc5cfe3d6f4079f1212457d74cdcb164a12ede61a32f8002	1627281212000000	1627886012000000	1690958012000000	1785566012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	257
\\x706e4483c0f2d1924f447fe10c72f55a9ca121554381c17d9649b5592dff618f28fdc8891219882a9a8540f9fcdd9be19e1eebae85e4c12923b917aa9c69586c	\\x00800003c2b6436a4b0fe8d3b0d8747fc340a966ff3e54c3193572911fd917820b6b2102e8bc25f8b284fadf64ea40c83a18dc07f85d65e14dae36d691f0ccd6a1cf74c42c19304a21c150c753ac1c2d8287513085566f456e8c67ad08284301d60957cf19fb3a1f85edd2b7a948275a9d5bb8b29636c2a7d9525ed2d5df4f30584a603d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7d2654c34e69686c235afb3a4f219737e1b2c0edafc42680b18b2c38d3d650df006295e0d62b4bd9bedc442c5b9994aac426046a9969d3178d5fcb3dbe3d7109	1625467712000000	1626072512000000	1689144512000000	1783752512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	258
\\x71c222b094bd6b2678acb7455cfe4ac484b779d642a63ae8c82df549ce34d9b8c6fcd52702388f900c06201e190c781393257a54ab369bab1e790f472a564aeb	\\x00800003bb97570446e335165d57b1c72d8a99021b2fb3603fcb8007b537bfd104ea572239c0a2dd9c71336ae9d8ad781d115483e059d18ccf5b417d3f45820eef6d1483ba1ab222b40f4c1e6f5e83155ada3b2fecb3fa8b06869343f9258bc7cc7de4cdc765a619dae718aa0ab3f97fdeab845cc851c7b2fa4e8994afd6c531a8958663010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc9677b484ea4c56d93e28c2fb8679ba9cd23c89bcfa518872cc7cc2df8b53267502c1ae4c4d513d72d4a2f1cca3f9347f2e9aa9b0001d40478ea25d87980d009	1612168712000000	1612773512000000	1675845512000000	1770453512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	259
\\x73728f2b85bed2a335733098ba51eb7fffad8dfd283b48aa121bac6655763e95767fbe06e36a3ec436e5d87fbf4b45fbc27c5f6f9acaa473307c20dbd87d85cf	\\x00800003cd3f43d5dd34721be430863128b10f6e0e6332e7b94f33ff24093c0e0c1becb8e6325bfc0cfc546141c0ffdc27036bcf4c4728300a3d3e44f46bf16fa859dc2855e025ebaf2563fce62eedd65c4a8b615f4561796fdcc7beef88eb64dabb2ae6d00aec121582603867e972f47d0819504c4947ca8c1b39302dbbb4500a713a01010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x84bc27f06a6716caf126a493d7d49a2d647fa82d72c4d6cf5f939ccda008906668038a0278e7fa08925b88c17e2be29f98338857fcfa3c84f3e8691b86c4fd0b	1640580212000000	1641185012000000	1704257012000000	1798865012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x77a22e0f78a76ea1b7e10b8f90ae7f205d24467766d5f7e1df7bb0473bf3db4af0aa106a15750dde332051583d33dad2f0dadc741bb8275d6062addcda08ef4d	\\x00800003dc3e4f60c34f7c3bbb05b65b3aad7e74371eb9235e75cd409ac5a7a87a0b6b6a3e473a724d29aef16006c393105604316ae416d2d72532b5a4f803005f2cfa1df9062297e307eefb3c0cfe98da3516b1cb39875ae3d710ad4b9dac2cc0aa8a124341b57d705660fb2335aae43b45e8e4e18eed9e6a783ee6f44dcda8671d8e25010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfc3cf2b2889b3e6add4dd488d2e8c6b9b739a325899be7e52edf49d3d295e2f7906d29cb2a8d3388abf3cfb0e497413cdcc1cd369ecb2b992a5b94088f9ef006	1620027212000000	1620632012000000	1683704012000000	1778312012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	261
\\x82860a3538472caa38784025bce5f9cdc43caba12e0e31a4b6e8bb27fd9f48d7c0f0896699832878439cb854c6c0fc3a062647304bca2991273aab660ca5246f	\\x00800003b3176bc0c605d780ce36d56b09a9a5aa46022f4fe9e6b32c8cc0227d553a80bbe4c9a33f8b66818216e37c89c152a0e1f490a8279cf59997d4d4131ce69ba9a994b1d75a8a33c2cefe28cf1c54b8620ff6c3c90ce034335870f086a8065c65aaa8fe78a530ffd2a4d5832af416262b5b5a73a7d5aa1a2fd111cea3059b221a13010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6637f59af3ff18bf9a14a335e302795d253078f96b7cc1c62d9d2fbbff939fc9f01a94d525e04b929f35288ac9394a3f42ec81fb3dcd6cc95afe6352e295080a	1628490212000000	1629095012000000	1692167012000000	1786775012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x87f265e0722c28717a56c3325731f57cf53a926fa35b1997a13805bc2f9696f74fec9603dc48785e47820d18f53af1a65c5b9980a1819a916843070edd457720	\\x00800003aa33ce73ac0340bf734f93d94f35d7656be14e439c547ea25de0a70c69796086cbc578df89e1adad65b1e7d060b81c432d68ff26ff104fb2ccbd01594cd5ffe35ef91cb9e16ff4dcf3d736af97bf4fe72676155608317ac86ff2aa2cb03cafbf2f01395bc8345a95c2ab8d3f96dafe67fe2ddc7b3a742a2099a8e985d337dadd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe9c397c9f9c8664d07f12f443e99f4a14c220c6839f4bba6cd1ca46e78ec68a84312326e089dbd4a468c36653ecaf7c919246053e49df946e3944a900660fd0b	1613377712000000	1613982512000000	1677054512000000	1771662512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	263
\\x89068b8654ffd1a38a665bf063f5edff18cbe08bee816a85ae884b63292e9a70e1cba62adbc461f8aead722a42467da659e1f8b3d3e4124275899285088a4b58	\\x00800003c1bb03880d72fd92293118652776a481d7de98b34e334506f3a6c985633634add64c622c6ba4a8de6ceafba0734273d7db0a004fe187a40fd0a1041c4710944f77350c4816a12dee1f60088a1241eae76d6c5ae82e232ea6f558ba5e99f278f18302eb413d835d92ddbb0343221be44dc9b7bf1b58ccafdee401abb2d57d0a01010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x267562ad0f479b1e5fb47908f83f7ac587533d43a3906c15d698529061973752b836069ffda6e92ae6f30924c550ad0949e327944da473c709eb5957f3dcd50a	1632117212000000	1632722012000000	1695794012000000	1790402012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	264
\\x8a9e7f5718cc1d693ba6ffc72250934d8d2acd49fc7fc2787ec7e0b0f3d560cdc41ad565ab4f38a26ba7aebeaf7889947e6787bf54e60c7f8867663b55e48cd7	\\x00800003ce45cb0ef1dc95ab4bfe72c1534c67ad55be92b0ce2ea132fe92cf285a468cc26ee17b14f389fdf3356e099ae16fba3f5e9f4b9cafe786ac5f4858abcc623884d6a45da23f9b0a202011aa13e8e9da32d415d14c7a70d491556fee3245ed1777b7c7aa2dd554621eda9bcc0abf869b35d9372be225790db3a72e25c67596ecad010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd9c1eb0cc48288ed0338c61566116fc9946c57ba76eb2e8e0c1f6b08533d0cf145b47f1547f35162e70e363d99e5270252cc32c9dcd89f88fd0b940ea29ba20b	1629699212000000	1630304012000000	1693376012000000	1787984012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x8bbaa1a2e561ff58470312d8a622e643c81ddb35d298f657f368cc18f705e506060f470a52e586db1d6df9138d6b628231f1d81b848ff0dc79ba3f8e054b8a5c	\\x00800003c6c4d40a0e6405526ba5c954666a77c38049566cb5b0429ffd09305d5649e0b738a55173bffced5f35955404f1638128e9d0bf00de5734204b1c34e1fc90f5bef53f358079faa50af022b04ee2248d83f76ffda455362e36619648707cedb54d422a9789af9bdced6e398a2312264bbb758f9ef0a47001e9091a8e91b9c3de33010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa6b8c773aaeef9b21f59f985d1a09c7fc2a429057531cc6343fd0eb984205b7a5f5249c3341053629a3456f8aaeb7f54e971851a63bd3877f3c5a4fc70e0dc07	1634535212000000	1635140012000000	1698212012000000	1792820012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	266
\\x8d8ae1e81b4243d6f6bdd88253cd361aa65f04beba30e35eb7f5121b8518bca3670a3835d4a5aafbf42299ef425fa8364cd2e20bfcc23a63d5ab22f521bcaf49	\\x00800003cabe01efcc3b02c43e580521271b305af3e833fdb6f118a06b7aeb844595b871f989264ba864e5ca73c8942d45a882fda65dc1a4f9937039342f40cecab213cc1d55bd7390ddd3a23dd7eb290b597daabfdcea9869573a1822e7e9c4ba9c281830a3c84985351b4db62caa3471a28797ec3ec9401c48b5a0f00ab5ff0a9223a9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb8432443140b6106b9a6c4eb4949af28fc8b20d3593846c0de7907267e444809340bd191c24d19c83dc374227ad55632a12c32e5d4cff0a9815411d66123c003	1614586712000000	1615191512000000	1678263512000000	1772871512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	267
\\x8e7638d6ab628e7cccaed4c1d28afe7847d3cf9d2317a32f8df5a001aeacd249d634e9db433c570f204fce3aced5d06fea9d9556dcb750db7e8b2f325a176885	\\x00800003c99057d5c44abdeb9ce302ff5218b1562cba633ffa85019b778be32c55b86f120cb2d96374a3cf6034267857321e3b9524cd60b6ce7984ae06ff3752cbc7dbf62a439e8a68186e1e246fc5f5dca68e3e8070a199ad5e1b73d0e8fd3fe566199fb12edff50f7a29c7f543dafb4830e2de0a7273cb66f086102b8f0aea0e829837010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x09f7fc03493453df84c5c7acabda4260e1865fece2e90cda0aa676aeb9925423cf4ddfc6d136b731027fac3121d3170bd749337be45c070f4e9c7920f66a9e02	1619422712000000	1620027512000000	1683099512000000	1777707512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	268
\\x8f9688303aeeaf4b420374914a55934713ec49f674966ddf253d614e466639287ede1ba36a6f6464bd577f7c98213d53ea5c8d5790525434cb1d0f84a324e2d5	\\x00800003c602609e5e0a64a78c88945d1d86ff2b20c2dd32567a79273efec00f218c7f63dfc3a8ac71974077631278051a9cdda1a021ba7867611ed8ee2e908fcf191f924099db54a6063ce2f2fa5a1fa9026ba920b6bb4e9da6670da49be0835fe1f35667657c9c3215e1a52b1d758ec61b460c44bf66f2c581155432c68be7025ba993010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4dd445f8dda9b87d9a9aa97c93a895dab8137eeb537c3a363d465f29b64402009a98037c335a3573b01fcfa5792b08cf9eb23f5f476ca55ad145018109b5b30d	1633326212000000	1633931012000000	1697003012000000	1791611012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	269
\\x93a2c8538350fae58216a6a74325296321e22d407fe01a826a9d28b37421428e7c23bb29f5513cf189f7491d9fb57a7a799f1110ca79a63353c90805fbb92fa0	\\x00800003b767fab05cab8075c28a4d7b4365eafd928a8355e8962403530fc721fc8838d91f38e9f9e65807cbf36986e1b8c4e40448310e8e0a419957905ae6749cac48f47d229a3bc692dcd7cea4f226478fdd134958a47d3f5688cdb90a972e3ca637adcb7adb7915561a60202c03fe4188007ae53dad2a7977f450acf29391a77fb6e1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc762d6a09bb00bb78959ffe42e28197c500b5758e3aff495840379af8752667d55b8f72f4eff15b40dad8ab40fe2fae268cbeb86a47364f70c2efeb4f61f4103	1625467712000000	1626072512000000	1689144512000000	1783752512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	270
\\x94725651dad0564b6235d9e545b599202405c3c21f5944975ded18b1111526f884138a0822abe87ef7ac9ef3ab0bd2b8f6187176396a093b4c64cdbca843062b	\\x00800003cfef0d764a371e18e514fce145e03940d80b9d95dccf3079c49cb75ae54a490cc4c04dc774caedc0ed47679428944812ea4cd07914b23b4b4d5516bf686b554e65d5c36c2437b7d4c896b3d5ff2ab65ca8cfa9c689f843fe44da96ee72063a6f099bd4fa2d20050b7137ff1b8b7fa67003de5162e908c5154e197eb9eaac48e9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd1be06fc32c1414717d044ad2398f7cfa4db6d7d992d5704004987fca8adda7bf13bda27bba37f0f21c0c67adc8c11f47c4e66f9a2a6167044e002c972b41f04	1610959712000000	1611564512000000	1674636512000000	1769244512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	271
\\x954a0eab4c2da6ef52682d93ad33b31929b70592d67229e057914266c4d6a41b5dc6a1aac4a43c3189110f8a52cb3b620b30f2c0cac4584eb7a60e8752994a81	\\x00800003a3932606fa87775509035ac5f90d2a8d4a56c77e06c751f6fec23492aeed49e41aae7461f18d189d76034dea20373e4985d8efe2e56aaf54f5cf693666e3a4c9c7551bf2c01d12e60d529d430c0e6f778261a044bf3ecbfee0f36f05499aab8e66977ca5c0a156abe6a82ddeeebc2fc43dfbeac3d222cdee551924df7b5bcff9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x058b0fd603f95afb440f16f534885e82a17cfbd9398f91c961ec9dfb18aeb802b899ecab89884726a243d5e7ab28e52f0c45ab0bb23d7408e4ab81abe3e63b0b	1611564212000000	1612169012000000	1675241012000000	1769849012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	272
\\x97722bd006fc3dab4570c0e58b945116e7dcd614dcb22217ff1addbbdf37f2b168d586b0e91aeb68f02831b78f6279da5ea9f79c3e7f5c4cd634d459b82f9ec0	\\x00800003a8d92d066b378c00495f14d5a022162801842d8e23a0323f0727e327f83a9cfe51456f517e14aba2df04c5c39d4c9890172811f9508a6340fc8bfe70b085ab2b3480468de5e60b4956d63cb248cab8ee4627a6019de611be191942fdb909f3b800a3ca3b0ebe3336d947db8e692ad5cae8d061c1b3f66f1d3f0cb9fcd5a7d749010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xebee79519ced4551ac9f7f77faa185ff5744d0b3f5f7a934b9539f4b487635f9682285be1579ebae38e7598b01ce8fc5fe95cf20f7907f07fc3e0983839c7101	1632721712000000	1633326512000000	1696398512000000	1791006512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	273
\\x9a3266ed89b9c3db526ffe0b985a11d8f95cf8b4578c88b73fc545ccd71d683991e1ca3301ae06807ca6bb6782d26589c0ceef66fb46530ef16c69a252210a39	\\x00800003a736e4be459906741c03e393ae566348ad9f3b60d6e38361c3d8d85f778db172a166386034d0eb7499bb16c48937e75f639afac9ecc2530ee869feccf8235535189e5e6df32164231dd4da7a58995a2144f9ab8c40586e654ee0931ec1a58a659c86ec45d76b6886a48c18da3b79806cd31a8c7e9d4239f13c97e5903a0b07d7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8644f6b6fc969fd4494a9c1cbd5bcea117bf149638d1bb06604b0a73aa0ac740528acd08949c78cdf8c83a35e5e0835512a87aff55f7a56afd0c301211dbfb03	1615191212000000	1615796012000000	1678868012000000	1773476012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	274
\\x9ed2de5ac9ba5460c1f8607fd1d5f3b8df4637a38a4d0a99004bcfe70f87f3d63079c66a5e1829d3ccf78afdd6807ba925d00156bf1645e8143cea2f3d328909	\\x00800003d0ae86ffc2f12a46650256cff77146300fc3ed8af6dde8956dd6bc2e45959790c8b98ca1dec1e44747fb30fb5a46bbb51887aabad1e7f108f495738b59e984bc89904edefc1c245b9e5286088109b785d431a1f9964c06aac2c932d26049c85b558cd9fa1d82922653b87dbda72765389b139a4ebcf611b77205eb63040b07c3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xaae9fd3a83ce2329a9992693c6ae7d2e5b1295b29dd9fac980cb4be2cad5e7049da68ad430b18a523c3efeb96030484a709f5fd915c232c841df0da0bcc95005	1638162212000000	1638767012000000	1701839012000000	1796447012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	275
\\xa42ee568d61e92e4b97e110948705759ff1aa6298a8b5829e4966ff7a7d014837f7e4cb2f84868bd3ee8042265b5aaa7edce3c5d7876a5f527f1ae20d8cda9f5	\\x00800003f54e49328836e41a9755b2a9849b1bef51117dd9bbcad5e5aa4cd6d1a494953ce6098c48849a708360e4200027a042aac71e96873bedf8c8bdd6afab6772dff44fef5715bddc1402601f003d4cd77b983842f862f6195942948df4d0bcd7dfd2c986c7f4bcdbe23cfcabfc5347df727db343d3b02a61da35ac7f84e84ba5185b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x60768e8113610e121494632aa199f2ddd05d372d54e8a426f8b5ffb79a32384c52f4a3a4ac39980395ed99bba452459be12d42178d51aa6d54fec8d62c96430b	1620027212000000	1620632012000000	1683704012000000	1778312012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	276
\\xa6722c084cbc9d1a36b7e4f42310d701e90c72ad31e4537a0e7562a97b6d0ebab7c3f355310fd6ac7e1afb29a227b7ecf1603ac14eda5b0f10227c5f83210997	\\x00800003c3a0fc1e9cb8811f036e1688718315232a1b1ad4ce6331183eb7f14a50f72f6f33fe3ef17017a1b31b01e0f75c96a58850c2e8b5352c76c6e539f6a9e64a69a48ea3147876b5ec1c740a72da3554371b0604d8145e3c97c673bea9fbaa22ff9c15c64ee4921ec42eee78a4b1f6ad4beb1e453d4573a1e07daf5dfb6fa8eaa521010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6246dc061ec02a36168997d29c309c30ecfbcfc0047c085f9fd865af1f9a0e6f66c8ca372f6fa3b53befb8f06af59768f129b99429f372365288aa4809500709	1615191212000000	1615796012000000	1678868012000000	1773476012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	277
\\xaefae74927aaab666d95e196623c13b3f654a7d98a3ed09d03c96ccf575a536a2841dbd17e046fa1785b37cd7a53aa974b9dc9c3b34880eb5e1b05374b040c2a	\\x00800003f651d76e0f65addb8479c873904f4a1d3ded0364ede149e91148503b61cf4bee3fa9fcdaff1972e3790b450d888a2b3f0489fa9a40cc241b92fa75af0a4ba034508770ba1f6898889e42365758784ad178e06bfb21318d779675d0967363ae6307a3cd4b47a36206ec092545e7de53209dee571c2213005831d7fccff5ea7dbd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x157350acaee6446f3651109e856160be30cd4bc4cd5d3c8c285b38658efdfa82fa9d6cc51f60e16ca2e8d3ea5560cba7bb1a1120793662f23501f3c0c79f330d	1631512712000000	1632117512000000	1695189512000000	1789797512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	278
\\xb3f6956c1077b4275b4a9d831037e9a2033883f299078c1e52960f714c47e6be2376c5a96d2d0e96a5c0bcf6d912e85698c255f6ed54375ac5d20855c2bea2a6	\\x00800003b9625c57dae4d690e6fd5955847968b31cbc69ab4008b9dbb751933d134daa4e6dee41e6539d4c2cdee3c920747a63751e04de36bc4ab8ea5653833b58385472bacb6a6085ee62999bd259d36709dfec1edb5535f916fe02c2acdefd1b8dae013d9b777cb42ff4206fdb71ad71af596a562bed01f8b82853a98ff899792a4f73010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x373da40170ae7e5ce4416bac3c034e4d7cf6a7609773d5b6774e5be7f0b0851f2f5c6cd109e2022e5415636dcb7309126bd3e2cf3c6b6fba2f10cf51c778fd09	1639371212000000	1639976012000000	1703048012000000	1797656012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	279
\\xb662e3f3a76c0a312d7bbbabaacf5770bd54f050b601d7979ca480436f7d3a54abfcc9ffed8ee9600ef64183c2358f7cde99dc16c92192c270dc345d8a71495a	\\x00800003be56e7e30c2bca66ef5a54483fa12f10fc5927678dbbdfd338551a59ea3fa9f6b768fc8cc6c5f9e4c5bdb7458209fd9ed59e8efcc4ebd37f3eb7fe2f4af374a5d80cae4be3d1015dfb4695efed50817743145f6199ddebc65cbcc2e2d032b37ebb0e5fb4dec52244fd590a82efd943aaeafb282529937577f7b8ae445bdb5f73010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfeb3b872e30bd522555543c9712480fc61d4c783cc27fbb961ed659d8eaf146439228aa3e1c21870cda60a9640dc67b8ef52cc33fce97e9c28f2df672058270c	1631512712000000	1632117512000000	1695189512000000	1789797512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	280
\\xb79e6200cb85b2813b64734bd51bbe8b8590b2e463281e3547191740902fd3dc76ba47a1fd3d4ac83d5c9182f10a6d89f94d0fa97e9a41a42d6957ead20aac01	\\x00800003e73a5be2c95117d905e960acef79bcc7925a1576699366d3e6e1350672ddd102ba2279ac331abfdafff3684db923b847bf04bdf66697941a5f5a37c57b3f7376056f4dbddd52f26fc3c0437488a91a8169bafbec2d8416ce99d3a4ef5ccb709d889cbfb9953ce1244a70a2578537b083ec2a937703e7d6c820c6a0525b63cf91010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfcf6283191a621abde0e84b1ca9860babf561bb8634dc714f5f038cee692f66f1187806ffc822e9ba64943a7f17feeb81573c9616f46e9ee77dfe2824f0ce30d	1632117212000000	1632722012000000	1695794012000000	1790402012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	281
\\xb9e60c47f7a1be3883f3c7e0f07e4118518fd15dc24178d6772c976acf6ac88733440b65b07178d87036670606417235fefa08fb1d1ad0c67c5fa0c8e95bdab2	\\x00800003c3587fe9a1596577a0182851dd85114f40e0243ec23154e1db94828d2050428af5965819d4aaf0d2e74bd78984673061597daf4e6bfca893faf767ef092ea8cae790c5ccbd0aa06d60b7141632cb537e87834d36b9283a94d36f021b0780044172809cebfdcaed3c28aebc0eaba71f245ca6a3fcd873c74254742766ee104001010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x39f2e5a00eddc1800f1c31a17f435b0eeb86d14bd2c38e097767b5d48e528a24c047c8af51025166bac8e616cd3e4b5559db208b598f676ff579078e616f2b0c	1611564212000000	1612169012000000	1675241012000000	1769849012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	282
\\xbb0edc1a9a735fb77dfa4fa50cf5e28033885310d608878e83946c7f52781c2627a32ff702ed9310df9382da91ff946c6f8ca4a4e0ec88dbc3a36620d02147cb	\\x00800003c331d78a9ddfc21c2ad40e4bb59dcbeed3bead1166e18f56386b30ce884b3571bbde9e506c3e5d54006a1721b20c020a636ea3096f3476300f44daf4bb1c7ec28ac69aab66f8b71a16c8dff6d6ef326448c0d2e18e0d526ac9601a3e5404abd766c57e505d3e0907ed724c47d200a637c8b5f7a1947ae44b8dc0dc9ed1cc7077010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb794d364e02014ce5182e47d37a88ddfea8b80f6ff0d87cabd3acffe25571a275eb8e2ce747ce4e75c6102ec298c4e798e05ad6710c4d32af02e07ee41ed2a08	1638162212000000	1638767012000000	1701839012000000	1796447012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	283
\\xbdb2473b9bb2ae6b9afbc574657353b3925a7cbbb2be7db9e68ca724dd3ea391c284bf2821dc89091f1b38622bd1ff13cfad5a584ab87fd695e6b7a7fbe40da7	\\x00800003a8e6ec19f76cca5d66b9cf0097d18df1e0625b14adef1a282072a8655982cd7bf41eceeb6bf53dcd4363bee12e15fb6d9b7cedf5f35e48354b989ad0d8be4747710d62b3271c00609eda144490b5b499bb96c040f1802f123d71ccc92883fb5dbd3a2c3d659ae2e06f18b396be1af8163bf76bb59704bdffefe85a09051ff253010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6823ceec4dcb2f281038a6a4804a83f078718a7abbdb0a532280abd22927eea2af0db1008cdc1384ec85729cbd6318852ceaca134001d51df2a96edc6baca109	1630303712000000	1630908512000000	1693980512000000	1788588512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	284
\\xbe96054877d2d2e9bba48317d3933fe5629952ace5beb0bdf70698d6478eb449b882ecb4acf54b19b93ea007173581de370a27b26770c7e8ab169052cd40a729	\\x00800003f0cc0ad98ec7e6c044dddad5efaab19858e416efbb964b2b324cb0082decf51ebfac85ffdd4c943908578ca357cc951e4fc2d90a511826abce78229cdbf63322b40df21d6dd8623650a7ebded4f6f5f6135959bdeb71ee03ea60f6a4179f41551acc798972f67e3ba47399136296eb2b2d43c952edfac192df65c2194e27c67f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x48528a8bdbfadaf8968e79302904e7867f550aa758a04e9744cdf91fce5d7a0c1ac216e6ddc278424a34aaa13b9c1b08380e458f1bb459e71b576174b61b6109	1622445212000000	1623050012000000	1686122012000000	1780730012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	285
\\xc0be1e7ce2a0c194b05c1de05b7781f51777f24987d379f05cc9b60cd4ecca6a388fe23c932bfbdfc98bba7836f5d8dc3b34637a7ce87440bf7a8ab10c4ee362	\\x00800003b7018fd4e16c318be11f7ea2303d5e896981a2da8f6d2cd8d9796cd23d1a83dcdb776bf405ad2662aba4f79c7a80e916a3d88fe024cd243cbc4e215c2f90c88df7a562c906fed504bd9fc6c1f1dff8d21708119cc00cb15262944834483d6f507e3b0b8e74d6f6bf42ef58203a14a584c064f929adc07a979637b11e45f651bd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x004f69f2c358ff6438931c422f5ba323c740932cfe5d1994cf6fe1b36ac4994c9fccc0d5aeceb3b6441f79fe7936b5694a67cc9b28ae7f3333795ee28c402201	1630303712000000	1630908512000000	1693980512000000	1788588512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	286
\\xc1bef14a0c4f3d991f739d576d783eda4e5cc024c02016169634b1178a99fb117e0952738b25e8bc6960ff320b12467d6b2aec782d427c6af368326d56b5ea37	\\x00800003d5c6e3281e9a16df6d86b4c154ceb53e96c7be0fdd3aadf85e3cc5c82ca4dc0a1421452cff94a395faed0296d0584d288eac588818869109df9f021b0c47d64eb48a047d6884d57fb7dc42392a41763aa55a8a4793fdf9900e0fd008adbc18c5d3cd2484815868a6c7f957f0ef64b4ae22dcc8acb6e9f8481153fade8421ec05010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x75ecb312bf404cc015d3ac2c3b4391cff5374e535e061d8a6fd5fe4611e3eeb239ccf999adf04d0f0c6b85454697c172f3932b249261aae32d2c92e0343def0d	1627281212000000	1627886012000000	1690958012000000	1785566012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	287
\\xc552d9e238298939f3290e271d6be8961345506411c4dbcca7855fe7a131477fc4cbe112342cde84b7bfbb5bbcddbfd8666d8d522ad642097d6cee78894cba4c	\\x00800003e2e30bbe459ff7ef607af4a1225e771b1fa39eec796e365e22139f5aecaf871201d8a27b80b156eb3a484c478be559a33ab42f7b9ca84ca344fa35dd40030599f98d59115b4fd15bae2085ed8ef936fa71d04b045683cc181ed942dab1c546d5272b4efb15c2ec78b988de0a67a160bf49e7b1c5a54a1d9c2b29281893bd5263010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe0a466a6f9507fdd7ea3c5131db42ed4e3281d84b3ed0480f220ec41a8937eaed3c17d424af8f9841f27283c2ea43ee2648a3be894b058fd4a5fe82586f79903	1636953212000000	1637558012000000	1700630012000000	1795238012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	288
\\xc762f76d50ec4ad80ad144dac99b58edb6cd7fadb188ab5e460066ae719309ddd6975a35bb134e6dcfe3bd113f670f85d40370329e40f58256165d1980d8058d	\\x00800003a5569eb66d712ceaa847c9b96c0136213eeb234ab973f1c352b353a18f0832d72f5007f1bc2ea3b5714fe23369989f74fce2acd5c94c6011e63305c2699d36769a4bd00f27241a35ef428657fbedcaeb0d3cbdaf6d5ba9c382525a830626b2298062a41e9104a724b0680803d4c956735d3c9383e1842ac322985159c71b7677010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc94a00b262898bd34536e4bb787947bea15246b8538173685844dfb8942436e88611063418c2d3613068e6be930ef37ed54b9a455d4c7d1b8c6ef5f5f69a530c	1640580212000000	1641185012000000	1704257012000000	1798865012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	289
\\xc98abf561dd9206041a366f1ee98348552fb51422701328d2a73555065440bf5dd3efa1a4acd45d53bace83381557c579fe07cfd573de0d21372e68c3f1e3d74	\\x00800003ac624100403fcc3893ce2c8d6bdf18de4e83ae3c1a72b0bc7943ed3e9cee411dafd60d873e2bd3a4aca802008c4395823a4a387ce2dc2ed62c01194de056ce97904bf6a5f94a10358f30ab72ced839d59bb708b60fc20aea76eabfe279e4a4c66f9dcbac270844612dbf3f929d11711819243920714d93dfa0a20ad8133b48c7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd9888feafefc1e995c13927d0b2ffbb3bb44123a032082db1c2899a7994871fbc061f468071f94447041d0d1bd825b030faec918d066de787e820891055e630a	1633326212000000	1633931012000000	1697003012000000	1791611012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	290
\\xc97a5e9e93b8b68f63dc4476ab34f3e40350d223d3bd18efb15e11699410a6a797541e231738ab4ae9dac03f99eae04c9b27150f61308871587bc95528898512	\\x00800003f647340806fbefc948dd1b8a323d1723756b5ce3a74b2b680ac73a4495f4934cdef78083c828154e31cad3bf4334e7c5e93e36240be89fb6070399d2e4b90b14e60a18890f6d0319c16b963ccfb84a7bd2719e6388d9dd8fa86e418d4f990f2fd01cdaff7bda58c03f4c73239663d358243681724c67045f581b1b407931b3c3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8ced5ed7bc231969d8d878757d055b0354f72831c06de133610ec50065e07851868bed63999a18c8e6b7ca630a7a64516583f36feb5e62eb7916670c9b7cb50f	1616400212000000	1617005012000000	1680077012000000	1774685012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	291
\\xcbc24f87fc9af9af1aa19f64baadd34a17f4881f72f0d6de7b7433eca3823eb5ad5719ad2baa9a55d54b65f65fe5c7b051997b4283ffae3265f022657e4e5ca3	\\x00800003e62f1f53c5a9a3e9cf0c63279090bd5816737a9c9d49d1bbe03d613fca9fde67eef5a3de2b50f216893f78a32299a51f1f09ca4e9e6251752236cfbf2aad21824e14dfefc27cb68faa39d27350e4853bb1849aed2c1d804dcf04a757cd6febe7d7b5e306ac7afbdfa7113cfb757b312c91d023d151787ae8352a41d4659d8f55010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7eaeea2b5e954c2fe8dca10a19c5ce5d7fc04def7f2a15937c73e41417d97925493fc8816a772588fbfb63966e134e9e1274dbc6740ca267a0f7168a5514e90e	1617004712000000	1617609512000000	1680681512000000	1775289512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	292
\\xcc067dcfa7c4a25c4cc0421b46cc83d125c70e5958158c49b7324a3d70e0eabb9f45658c6c6654483486e63793c636f9592501cfddd33e52f1e6c05fbd93b811	\\x00800003b9ada605b08d2db3e2c76c089ee3e4ca6a61c6ef5ab682aee9164123dde4c91c5626b0899fe085d8994c876fcef470b9a08cd80c4b40b5b7cddfe7180686bdde3aeb1628d546362b39c92f729f5abc578926fd09bc49ae57187b88de3aec70443daca28de22acae608eea01ea93fe19a063cb7cecd2b30cf9bbe81e37e8af857010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe43c785d99edd35f7a3aa8ed1b61a19ea56bb66b65fd7f56b41487a23731ceb1b18f03a7283a66f611ff337c28dbf9647b68e1b74295eebfdc243bec37e97a0c	1634535212000000	1635140012000000	1698212012000000	1792820012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	293
\\xd2ba01b2da9870f1c4edf64d5d8e27bd0be2e40e82bd61ccba08bbfe0ddd1fe99b2233e438c3eb67dad28da86f283a9413a898aa4ca1cf625cb242d3e3d7090d	\\x00800003a7d182b326dbebce75894aceadaccf68d408e05392b441efa7a11afd907b2ea9d7c7cf457fec9e3b4d8bcad80903a7a53e5dd25e329e2aef2623e8bc8c672c8ecd6e166888ad505bffa87a1c95c5cb6a6063b9a9c4dde04c8fc276f88beff02aad3d4104c66114429fab73f27b0fa32ac27af550e6a553d2b6a686cd62ea8b71010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdcc23d88c74af655b16f27b9559303597e850b947c402769c3480df4121267cc2ad4f6119a0bcbf8ecab7cb3e8613bd20198d6cdbb5ebf37c0ecf7fe71e3880c	1623654212000000	1624259012000000	1687331012000000	1781939012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	294
\\xd4ee01bd144cce419a9ca7695944500790163dbedf823cefe69965a34a7f7ab4ee0346d05c856db2469a403d43871cd0141118a31f590553e0b5aa38b68d7c49	\\x00800003ce6dff79857ec7c96b616b1490c253e7800f0906adfb7aadc1b4047e46cb2e500d053ab72f6295aee49c5f5827aa9ecce62f8022f0b1bf9f9b154d19cb93f04bf9e32931f8d880ab1814a068f1bdc202d531cf51dda9d19c15bb3803aaf8aa3347d2287c08e33ccbdd3929001954e9007fd5a3189a1fb76560c0ffda542ed42b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5949eeaab99b0b050686e0989326ac262dad33086673ae0b78f425c783da0b4a24dbe129acff3983462a286b03099eebe06b063443db8f846dfe0a2241a9f601	1637557712000000	1638162512000000	1701234512000000	1795842512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	295
\\xd496091dbb52e3f26397ed7a11ebcdc2fc1a65b0ba367ac7936467537b3c58b4e7a9b43f8987b8d3f511577249a2f422559eabb83067c3cba1edf4b3f536a24c	\\x00800003a4688dede2be85aa4b4ab3c576d57b88529acab9c2c6c4d939fe20dd0243afd11d9928d0bc40f80beaee54f13a5be70ab74d16b3845053e2edb0ce9af2e84f2ea46b9352ca76b996e73fa85e283244f286a4d7bce6413de227f6628c1ceb22aa8e53b59c4c29e21ad3a0219288c1cb12e6b513a7562fdfbed01a912f8e4e7761010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xec6a5064d60c8320adaa44caefc7dbcfa58b0f4f02d6f71fe0ae1ab81c21b7ac26189850616be939deb3f4c5235474bce332c26d46e23f73929d59c78ad8dc00	1615795712000000	1616400512000000	1679472512000000	1774080512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	296
\\xd5d64eb82f3946c723f0ac20837f63aebb090efa4477cc0b3032f3fe99ed4dd3ed2befc6c58f9fe3c7da20a7928ff63919528eb9caed792034a05e45b8c3cfea	\\x00800003c551e529abe510d50c990c01eeba66e3888c9fca1427ce2aca4ffddd86beab385f0a341b2ec3e0a1d767e84011587236bae9f4a6de096928e7357f6b0a5dee39a04fc987878a6ae9ab4d076aff7f2186fad0f2090e83ee0ec802919c9128829831fd1302e62be1eb531398af863b09964a001b9e3f56f5f1206378165f44d3bb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe432f410e147381a4ba415bdd5d537557fd1d72031f20dbddfde05f009f2d6195abc979b236a5e3b5b937e388f9bc53f26b66ead480d266d9a0bff3904031008	1629699212000000	1630304012000000	1693376012000000	1787984012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	297
\\xd626c004651f72b5037fb91cfad9e6f093edb1df033b00bb2e5b1e1abb130ed9ca21361344a5443cfeef47489133e692ed1b7636a6905afc1439b889b7bcd386	\\x00800003cc60c907929744ec9b9668778f53f252b2f0a9eaf50fab8f7a9a1eefa73d66616ba09fa1057cc83050f42122be9f1b01bbb48a1340e90c4621fe129396d16bdd75df13de7de9e630b3a4bcb01bfbb422a2cb25f0e8a1719469e60df0ffbeecc45a29d3b9ef39d5515519207926a23ff3d8444a88ce69612c7710603bb4a5c8f1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe1ee578e54e95fe8ae3766f000fafe8a645a269db357751c5243b73eb78c03907ed03ec70c311b95d562b9000e271980a62cb74019f97f1fbd8c5cd1c0affe0c	1634535212000000	1635140012000000	1698212012000000	1792820012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	298
\\xdbfab74c56957a46457597147215226efcd61ff6389b7b65258d8fd43f8cea57955887bea7adf0ef3eabd9ef1f7591db5731dda1fdc5c2c6ba6603f5e5a909c7	\\x00800003d42c0d2d74e47b93a10c4684ac98c19a172ab77e88b332bb54a808055b809b9e819c41290d3bf178857539a9e06feffcf05615ffa262fdca82dc8d6afe52e41d950e1656f8869b390e947279ce433c2a61f712f2ac9c5159a76e80b6b8a6b43b7eb167fcf5f99168ab03eb6685a3f469dfe682a7eb1e2aaed0d2b6502e2d3991010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9b25d146d2439b8992df5fef257da890a6d290361c357a4c6535924b7b852a02a03f037775b0f4ea5ffa1a89a5a3e2a42f3773c2c73c27642c162f0f724b120e	1618213712000000	1618818512000000	1681890512000000	1776498512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	299
\\xdd5e8da782fcda738447b958dc0a590af29761839a9274840086d0763f6129d66a251146cf7acc3e9237b58cd9a0b283b681a194dfeda0d0df13abd88947eb1c	\\x00800003c89f53247e8481f36aa7cd72d75d4544629dfbbd0f60a9b10d9bc7dd8b354459a7d820290d5cfaf6019f90ac67698bb35369d882635924876fd33744673e4ca34bd50da591b79c80b3eecbdd3b7d36b5745c86db4dc610c6d5f23c1ffb037b12e18a0f761cb2eae754532a95fca4bc5b02dd5c7b19a9eb05edf7daeea7e67593010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x483fe1700dbfbbcdd9c7bc2281fe677440a4a345622f4354163babd8a1384e61fd320013cd35ffed4ad0ea8661f381545c064a9d4157c2f0f67e8c729cfb7d0c	1612168712000000	1612773512000000	1675845512000000	1770453512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	300
\\xdd5abda152d9567cc11ca8493e0139c8b7706f130a1e5d365b5c60ea7dac83cd3a196049406d18a96a96fe2e1de3c524b3e7e99417bdaa3ec1d57b5f3c78259c	\\x00800003d52b8c3daf8731c6b53bf98ca17625de8566e3fd664a22d49906d86df266ea925477ba5715755d28da11244e7cd0f87acb200547a611dd24b59114a13c4a4b595e4e50d2a1ed2c83d2050dc6ec4c9cbbefbd917821c1bbe8c4f8543be81c0bec72e9274cd71bb4e2ad0c9fb124bb5b650746e610f8d93ea7e4ffca71fe3c8787010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x85b8818a667ac718576b8a168bfcc786ae3cbc6a9dd21fc0171bf8802d79fcffbccadf4521db16349cffa7eb0e251b2e5cb550e6207e200a77d99d3af0b66402	1615795712000000	1616400512000000	1679472512000000	1774080512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xded2eb1fa311e192960d65ee15c491d3552ba363363cb725c5f430938886adb13c540b1bdbe132fa0e3f3ab8300b01c71f04256b2d0b7ed5d45ed0318a5345f6	\\x00800003d37c6b33071d39f03ca9ba39f2f7140e6acf0daad46f2a8332353e840772b8f9e824ca28074e6190bf385068fd097c73be52e7d65814db448246f2523c4e0dc0ca157083174ad4d6366cac3b1db337ea2490b9f3479066e940484712d5c4e557fd0a1275677e47fa15a2507be5b68279381354e98f0592c3adfd6fbcaac7f1f7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1208918d4ccefd6c396cf7ae1e1a7975d65717b0ed5b506a72aaa95dfd881b07eb4ea66d8556a55d0850a819da4dd8f660fb08257a740a42d91a63499498e600	1610959712000000	1611564512000000	1674636512000000	1769244512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	302
\\xe392a521f62a7b90d2a874f003b7c61fce8a2752ffcf9493e4a71e9d123c2205bb683e5131a469442ceb785fdde5101f13b4ee9aa62b22533e35e172795392ff	\\x00800003a93f0864cc81105f0aa83a5144a0ad6069dd49f2011e67fd176f6db7b5476c84d218a949ae908e01e817c09a8466783687de08de933c4b323186a3d3189bfd513e409c7df8fcc4601eae2fad708f14063c6d73291925508416a515cdd51e6f84df4954af82698e36b89092698ca594a0f90b20b117262c85e0d03bcd47cd5739010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x965d49ae5f6c8a0d841bb077ec981d339342fe112488a2dadc523d6ed96906673c9ff74cf76e5c1fc39d701eb8ab5fd4a9c512c212b693ce27ef7e48d3c53604	1612773212000000	1613378012000000	1676450012000000	1771058012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	303
\\xe486b37b74a97feca8a9f06ef82c22b074c12af9c94e5f9486272c69e631ab4e79597a7f493b843722de055da9c9f27f1d062a4dbb33ff57d445f360742473f1	\\x00800003cca5f9a77cf9ab184e68836237151690c88371692f61331e00f957c3923a43749588f1c9ac08e5a9da5d8316b7c6736e0e5eedb9d6863158e8ff242f4454231a54e456e99b701ea48c9227041f844ebcc10a1e4d74ae711bd2a8ee0299bb6b6a47f0219430b855eedc6eba968b87a15579bb654601b4bcc79e7c7e4fec25810d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x235746ca08a2a35a35967e9539b630a59f20f9dffa44841d648aa62efc00d599a529f931bd15d50fb53fffe89694253736ab404fd8d21b2d1a22e65f17ecbc0a	1627281212000000	1627886012000000	1690958012000000	1785566012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	304
\\xe49a5d73560143d90da155e009df2e729e9b00a77d192e3bf708fbb12520ff7b9cacddba1c19be78b17161a6f8bc42ba7f25959f663beae70d6c48ae94ae77c3	\\x008000039c947e2a6c680b5d91bb639c1354a4c4f5a7f837c2200d28422ce7fdbfdd3b114b021e926f41e9bc844eae4f7b20d616477a0a3aef7b9238605a493bb1f240d5f6daf82f5f608ec63dc10bfb09ea93a86c3cc02045bef73a8a5dc8ea0d1383c24ffa222c5b0fd8cc1797f307316146a451e342601c703fe659c7def743a8d24b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x043b18c7b3b0ee18e6e56338d07ee1429854180534c0b3143dfede3bfd0a4116c783baaaae22f0419aaf872a9067d87df00937aeca08da64a49ceff9acbcff0a	1626676712000000	1627281512000000	1690353512000000	1784961512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xe5ae9d320be69fcc8b9833409ce0a7312ed85bfd5de079683a4d6f744fe9dd65f387bc0e0bf3d5987c3ad869c07924bc697adc9a322f106d46570aec42b9e73b	\\x00800003cb1d60f93a8d7c4c78cf72788c5ea97cde1e46a70b1c1e1d0fb74f9821923e8d76224a4e33a2fc3fe25b1c0673767d46bce6c234e9ed8ba0ce534624e43277a76f776a59ad628f6211fb8194263db3c0c4b1e3ec71d595395963b0e6d233ce63780b463edb8ca7dfe2655dcc27f44bbd841bbe3171a1530e893683d881682e0d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8d4a2240a7862a6e8e8bfb797d20336482ec0e886797c0775243aa5b606021bbbb2c0404455db77cd8437605428db02a51d11fa66712bbe7b466afaac0bb5d0f	1633930712000000	1634535512000000	1697607512000000	1792215512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	306
\\xe6be15cc81552fd8179a064b09047e9c2790559b1f7743a84d38402c77a42802c345098114aaeef45a4bf7bc9e2f9d45871b9a0906bf2142381d89531024196b	\\x00800003be92c70ea6c52e273523c18678d6a33c759af5a7ecb47c2735670b3fce6978e6f02921dc4adad8280739ae3a502904da878ed2830233a601a4f7055f916cbfb187c2ccec67bab8ca68e08d09486d6c865ae9e54d3d8476e9b992e67137689c5d51234fc439168bf7ce64543dd1766e2aa4748e5cb34b0d605a2c5c7337bb05d5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x650ed9456083b692c1a9f192a5a9ede4c74b1669a4315c58c47bac7ad7f877b874c0d91da437ad218df05a963c92b283e75d5bdb8bf9e48ee611abcda44a6801	1621236212000000	1621841012000000	1684913012000000	1779521012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xea36b54f4ce376add3fc5af84d7b42f99f3c81a3be3bc5fb71f6d9113cfb791d374fc8ace8b80286d534c21e0845d48b9587114364b4e77f40b5693a8c3aa9dc	\\x00800003d477db2f88060e48a1e3fb8586289cf8e0c0700482f0d85e64ce51ae8a31b3b5d34bc449316a69667118d9a1d6805642a3262975dfc25fa39c95aac9d5b8dd0b6fcdcb4512bcab75b1f03779ce76fb73b2ed4b651775ca84311b44cda09a40dd8ae544153a71aac2fb54bd1fa35a10210f92d925012f206fc132790c6ae5daa3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfbb789cd1c1fbb4115d0f9f82f6bf5c793f0be11ca39418c50db08ab1dbdd8f181861df5e8bd0b83493b98bd0fa98833924dba1e725371a1b72c43947561800c	1626072212000000	1626677012000000	1689749012000000	1784357012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	308
\\xedc66b2f5e1e25353a99a6aad919e919dd546dc6e2dc3d4d14027c410db48cf5bd9e2f4dd89e267a5aa912921baf30c25e56455019e64900eb48215209e4a6d8	\\x00800003ab9acf46f6545cc3210d349e9dab28c9ab7bd3b654c4271f17a4d0b10a5cb343a8310beabd54736c18c00686edd1ac0e618948c4daffa0158ca2283fccc9de7881997a8bf97047c450b5515dd2ad6ecfc9b60b7f5b03a7b0264a06184513eaeda441865276a14f8efdfb2e31acf4405393b3d492afa91e5ef69f051b3fee76d9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x13e42257a4a33b4091324ad8cde9da5eab5e70166749fb78b74f0fb2f054d83323930e87e3dffe46444149a769398e36dd96c2a38caf0e5b94f606386f15f607	1622445212000000	1623050012000000	1686122012000000	1780730012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	309
\\xefba1ed31ebf941409900bdeb7bbe3c888b98782ad7fed1c72d4862d9a021f0a9b58d3321d7b1baa888ded6b4d683e4d0ab0953ed7f82da1630ebf020401487c	\\x00800003a8c6ab4a6cf086b2f1c575fce2a587216b5357e233234f43e7cafb08a1dca800974e3438a6883f84b14a15afbbbb15f1f1c80785bf73594cc9441a9a699c916acc4be4abd7459209aed1fb2f9f0c4f05ed4be445c22337d79243fc8d77ae23dc9b2b81067e17767cee88d64fdeb6dc95e212bcb37d77199a9c109ac572028ec7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x22b30e52cf75e85b58a30a801954044ed0d91febfba43f73d2b6c983c9a2cf6146586e822990f9e10632e3dcb25ee4598a1513b2a36d105412738f06de47e303	1621840712000000	1622445512000000	1685517512000000	1780125512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	310
\\xf1b2d5563ac53b25ea8f47cb1f0e97237626cd9b6f7f68eebe33dbcfbd60a4f838fca6251dc144288213e4e11e2f9e97fd86103fde72255adab5ba8488d24654	\\x00800003b70f9126b806dbc5bc23090b10bf10d453651568b1bf24cb3e0ae13eb913ee0477b45a00cc167e56cacff33f1e16afbd1845c139a9535b2ec8a4b4d51b7f8ac33d58661637ff9acc51c88e4ad10ff5d0c549d82d086915eeea7c5e0d644cddc7b487361ad7a21e1d1c6622febafdb9477df1397f8fbf5a1922672342f00ccc17010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb64988d1b14b8f66043f488ad7ec0f1e37f2efdc8b6ac645703fe2fbcb4495280b1809e1eabee83c434b94d9f84e5280c7aa658e5bd9a0ae30ac970699b4dc05	1612773212000000	1613378012000000	1676450012000000	1771058012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	311
\\xf21e50b3bf037f5b53f8c0b58e563aea0820834a51b26c0b83dd29953830645a20689b32b8c0c945219dc454bbacfc64712de3607a52a860b7ed6414013f705c	\\x00800003bd4fee818e3785ca82d3b10fcc07412eac9d55f1334d13d17909323a61e7c5b7b963afa23a11203271b7d93c9ec62f5d62398dd1a67d72bb5cf6c29315d4e0badff8a35c9243e9a6539432b7f2c3ad289050276133a2639b7e1dab5201a13405b65c9cd96ade783c69df547ee3b48d03730b8fb168c6cefea2be8d4c273334a9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2a7566e5e2203012da58a0c37b9584b9ba3a6dc6de3e1bd75670a2816d9ff12cf374592a0ff3a62f4e5e6df07811c32e7ff0dcb4f4760402848aed814ec90b02	1617609212000000	1618214012000000	1681286012000000	1775894012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	312
\\xf6063f075808642418e0b01dfb2c229f35a89eee3597d01ea41cfd539270ed6ce0aef4dcb1d5137f9ad5951d2e1e733d43b4f3ac4cbf9449de395148e206e79e	\\x00800003cd6c64047a8fb19d4b965c0f0b0d30e17f0457ee8e88ba6c3a366c2f3d11cbf0de76e18840a442c5bd7fb290f39c6d8b1e3d51e67944586f0f031d07c3f85db4363a02ff9653dcb4e6a12f54348d7bfc4b4bb7c40a90683c3ec790bb03d09051d346421fd66dd29ea9fa0a1a34b24cb8cdb4f8e5ef29a86b32ed5e49fb8b26e1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf0adb578441e8f0f242d86c0605df99b374997bea6ab5f85037ff2202a8d98c4ceeaef4d59102b40ad9b11521b119dc00602e330a53f02ad04dbb3c42973fe0a	1626072212000000	1626677012000000	1689749012000000	1784357012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	313
\\xfcd2917b36dfa1f678aa84e7c96d59123d138fa6dd0bb788136d4b46ca8cd9140c4832ae239698d74d8e7e44ba5bb7add7a7340df00d26d88eb437dcf6e1f313	\\x00800003c4d4979c63c58d1c41160666fec8526575afd8ec5f1227072973b8068a4b2988e32d6364776bad4570e36e04d7a6018c47563b76c44421b7f12e072787a07cacbed82188631783960e7092d1acc2130ad7dafc83fb7f9890897ec29843020a93f762f55d7b4fda453a72c5fab489e7c1b6e76bad221d5fbae180dcfd270024f7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6e1dfd0a0a66286fdb16d5b5fa0d33899eb821881f7d84d384630b09e5a9e5533216462851e83ad8b473b04b023e17ab36b7553c739f49ec21b5261a086c7306	1615191212000000	1615796012000000	1678868012000000	1773476012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	314
\\xfde6ec64479fcdf9fb00958e3959e826d3541a65b54a3071d78a64dd57dc0dcd14342443cf845bd0276a1cc8e8a95af5d6d2495dd91d9fad710ae4bcc90c277f	\\x00800003b57d283c5d5b331dac15e5aa6c50b9265578d96b27522ac8e2ec24c4bf6d487a269d9ff7a2ec908c99f6459b689de434e9b78e90e6d1e0f698c5ae415cb3db2c26ae6c859746e69224158ed146a7b9b477ddb6296718eb0bfa27d93923f83e96adc11652e4fb90d4eaa75a12499339e8c1c8057678f5315e2d00ceaeeef26a4d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x879fbf06b26abe2bcf8937f78079f0234a2d6fef9d5c452b2a07072d74876e1c8597d8e1a7b98bff475c148a7460b091e2c1e80cd73a0991a2990097f14cd502	1636348712000000	1636953512000000	1700025512000000	1794633512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	315
\\x06239cd76b01616b945475c4f173fb46013a39b1bd566d845d004dc2d47363c87547ae415962df497fb2c1a698c850471394f2de28e75fda74d4d43c695c71e4	\\x00800003ca46d9ba5fc7d8101845beff785f1c5d7e457ac3e0d3e0659f736a8e95aa2129dc6c4b05853fed05604c7ca182be61f41b27fadbd1cc26df616dbdcb55e86275d12224620f5920700f5c316f978f2c690ba6554b6210afe7c20490acd1447cc9ef2a1a155f15c49b01fdbc45c62ee188cc8978b1b9fb5c6a400e4c9ca7493f89010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbfb5a057d08fd4e686586138405b22a9ec1ed8c0c0b13c770e0005ed7c51b8871e18d609eb5685cf1c7434fdd43cd2d3a8c3342b388734df6fb41a0d5085ea0b	1634535212000000	1635140012000000	1698212012000000	1792820012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	316
\\x07fb0d81c2bbf7b702657cdbba8dc430f2af2b217878d5f64d13d7afffb5cac12e637088095207180ab59b10aea538ca1614f7906c6ea9b81cc14e81b8eecb73	\\x00800003cded3d980e4c334fd2378068bbeded28aa0c2302a3017ce63f38ba434c01c0824b8a5ae62adcb42eb2315c23efe19caa4489cd0e1b6a31297dc45f87c12634a07bd2f93b0c3b82f6d54fdc05909484bb28eb45582083766c1996dbf3e2b604e9c0dd8fe80b1a59e649046eff438e364126c0bba6943c9183e8a107d94bafb6c3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xab63b87620bb38c8569dbe6222f0110a38780688f0f9291e853c8f6afaa6f8018261fc458073d04dc379dba7a45f743a9ec4a87df8619673b98da5a7e5685c06	1623049712000000	1623654512000000	1686726512000000	1781334512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	317
\\x07f773a521729ef467dec6c6b3f4da96c68e8ca4830ca97e9498cc934c51e526649a13f63ea7ed16af0de14851da0df581f59f35b51a1186a87af61ac1bc6928	\\x00800003b7f74d8680a9854e325dc6d667ea4578ade9bb1fe4bbfdf8587fafc8f9c75e6e9d6bfe4ead1f3421ab3ca5dab41fb0d71843eade1bc0f84322ce694bc6ca8e5daba8f1cb62f95d8f1140b61a2bdf873ab79b2516fa91a484b97fe6ffe3efafb93268ee7021d6c859787ae0b27d61b037fd08fe28d2e08f826745fbaa13332a91010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4d6e30d60f6321ba28e50f29d0fd4efc6ef5b6e3e809963ee639768118ce6b838fb4e0bf75d19ba2e64d776cdbf8de29e02bbfb21dc1a8495f6017c80e5deb06	1635744212000000	1636349012000000	1699421012000000	1794029012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	318
\\x0bf3f0d8195d8011e3f45787edf72fa8c4aa204fe8aaf5b871e2c5ba5856f34919ecbf64711ca2c04ac8bd623ffe2982332bc059116e50d5cddd2c2df6dcca0f	\\x00800003baf84996fecdcf2d902499450d3c9ec8ce6a5ab933cb02a7a22a8535f1bd2931be8d8bbec38e91c6da28c801dd040238e04b04064ec8882aec99ebe95e95be0f1d1077e530e195c7d86668746f052c37708ed2a27ec84e5a6eadac4029e45cf28e1e2be0f9749523b546b32ba2856ee32aefe0b89829ad332d1507809fa68ac5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3ca6f84f5c1066907fb642e5487e43e2a7a46a6a86c3200e44ebad66ac6c227e9c71e015eaf5e7ba894a176919bf8e1451d9e9de4fffbf6eda335f340bd7cd02	1636953212000000	1637558012000000	1700630012000000	1795238012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	319
\\x0cd7ccfaff830701f171bce7ff4be76e1a784679dad8bb7acc28ff3e567676a8f4e582103b1fae4cc5244eba45150806b5ab28558fbec0e51b4802d70999b39d	\\x00800003bf5c6911290ac0a1b63652d1f174d0be0fb109e603d0829ac5d7f867d1d3ad992c7923c1caafd2216c61af5b69bca48cb06f7389a86a28ea83ee1c93b21bf55e6376ae527b2baad37e27ff1ff70871c0f01c4e82f8797df519589cd5b19ae6e1ff56bf2646a12f4adde7976e0dcd7cf2f06ac518749deb20c2a694f225b4ec95010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x54870d5065dc95a8d9906da8cbca0daad99d7291cab39366c2e922932fbf96af52d166aa095faa5316cc37c61134f2c71fd903589f58c9c598a378e1b5167705	1626072212000000	1626677012000000	1689749012000000	1784357012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	320
\\x0d2b83b1e399a603d7e56a408f9410b0535df05a9790b0836386e2f71aacb0af5bb6372998b975649b57f3038d0f7820140bb756f80ab1d5d14bdbc924dae610	\\x00800003d7258c6dacf913ee3b3ed15e614516af9813f750b6fca42bd750d02d88b5c92768c880bc6714171109adc352f14db63b0d49dbaaa11e1a5f54578e09e68a303bf57ccfc66dc8b2f4710dcda96600f43e89a5b93919f01a012534be2518876d42f3a9253abd441b06121a65af0f7808abe48d1cafee912b81fed3245f32d35b13010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x85c881928d8aee595d8937c6832cb34a122d47a4391a83cf6c6b2cf67abd7e19e2a0e1159e6ca3d02f5b596d6fe497727189e62e8c18ff1d685744f3b597470b	1630303712000000	1630908512000000	1693980512000000	1788588512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	321
\\x14f3a60e4ab9bf780395530ed88c5de8730a2deea6e6555c40defc499c65742bf0fd25e3d52e3da343f6ecb68e891c718448b87a451c7ef23f644a40b964705a	\\x008000039765c3543f1c92536e854d347652f9883976078001a50b918a164fe633c8a2efedc3efa977cd8dac18f9dc4d2799d179c05ddb71a69e97c16d963e9c448dc88b6e7a57edfb3fa425c6c6e76f83e15092ba808d8ee02ff5ae2275ae5bd07085260df494973e509730706cfd4ec8725005d8eec8ee8f591c5a009b0333fef0aa7f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x28c20f76b407a2f9f960ed8162ab0d5429535aa258957ab641d6b06e854f8b79b043370b562fc5fed445df5680e073bb7afede94cf4a64c389cd7cecfd117e06	1639371212000000	1639976012000000	1703048012000000	1797656012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	322
\\x1567d9361b4be42cc501a84d0d20d1dd22a49945588b71f04f2529f8220f7ab857511a9e97215608b65ed7195e68824f8764bcc317764886eb6f32f3c85abba6	\\x00800003c9a0f7dc9aed86fa9869c352c3031ee7a104761fc479cfbeec0072d67ff28b5bf988a6e4569067bd189b7c1af235fbf0c7484ab73b8ab04284e55d419186cdbcfa582c789dfd2a68e1a68eda5964c91b3a1330ba47fb85a1705a3a8ebd03f10ad4bb9e0b6577c4e22e7b489fb4717f7e6a9e8230621db6c73f6bf09e6412a037010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd95f13ce32c3a63c37bfe5b042be81dc8fdbf9071a89baf1f83ecd695d82482d55d5bf772d7815844a78ec21813ba500e57e29d14aa925f1c58c1626380e0200	1611564212000000	1612169012000000	1675241012000000	1769849012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	323
\\x183fae2d02abd79db229d3f1d0a8b1d958f8cc77c5a26aae49b4c0d425ce9db99f81bd599f9cf0325de81b546c82869e1aa416b2f937520e223e41d5cb0ab876	\\x00800003d2c012259992815c9ca73141dabfb392645f5806806f63911c5d27267d163f0f7fc0bd0d52a515f87b4f288fb1fce682efb01c54654e9133d9523f888309309bcc571c79b57f14982521fbf0da026a85f73a784532f83477061ae527fcbc77891812f48aaeb195ee6cabefd8edb3e91da151487f8d40edc9a732de9b90ba4f65010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x54f6c5f5485809eb4fcc559195ba488b125b69a99ba06bb239b769e3a831df9d20077ccce583298350e571cddf340a4398024529c06446ce83020fa47e22be0d	1617609212000000	1618214012000000	1681286012000000	1775894012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	324
\\x18fb77b11626c986fdf3bd33c6db9dda9d3deaab5cc0f899bdcc1c1f2393db2554dab403c42fb4e9bd8b42220aaf992ff65f74d8d31c30012bc35b35ac813256	\\x00800003e0fccfab27c294cc5ad9fc4178a422654950744099443875b9be882613fc66370b57d3d390c4cb44c04ce10f4eb624fa78cf29da33068ba910873345bdf9e0192c2a08e342961c1daf81550a9093ab37dfea21232303b1782d6ab5052b4dce30197808753db0a6d554ee48ffe82589abe1afa416e1cb8e55e8e9222dd188a847010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa84c831fc171e0b72272cfe65fc3be598c35ebf80e1ff6704f49505bbd2197afdee1c48837328e580faf2c52f2fbb38d680d6dffffe2d5d4f1e36e2662381b00	1618213712000000	1618818512000000	1681890512000000	1776498512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	325
\\x183fa7ceba1ba3161ed9c6932e8026d069d9f4067a2cea11065d99fa171e32d88f07e3814a6f09130def5a8876360fd74312ee5fecc1a4d6502f5d9b69941ab2	\\x00800003b9c37ddd5b9dfe1e6b3b9ac4d554bb1c0c479fb064b92fb593a6502c9d976967421869f687c912dc3b3d405f336b1ddc72ee5941851db32b73c720b53c831411916b4bb0c727d6b4eabaafd02d6accbac53143b3c15b8560a89f4d77f8e13456099a7a63151ae0dd3a6e0c7f73352af98bd44478213bc0ee395cd964e0a723af010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6b5628a7480dc649d353f72a19042bd4c4d77c7a9767c2cab795e9337b7cd523930793fcc7f9b7c6e06e0e24288532934413d6a12bf03263d04c8b4dbced3108	1610355212000000	1610960012000000	1674032012000000	1768640012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	326
\\x1c6ff9c8735c3595838e007ebe2583e33c3763b9fc62f52673e860a06942725ae0241ddb4e263fb348235c313e584a0798dacb4bea15277f6c176951c0f4086f	\\x00800003c6594781941ea8eb3c77a57296f623844080993c3f3ada145a607079197f66c8f959ab610e09c81b311b12cc448b3b3771506aef7974ac4c81f4eaa51224a1ec81a089ab0839b35c5f03514f2549e328e74672eda736c14c68d92f4df46e52a546cfaf0807dbe29ba2dfbc2a89ac8de917e6fc0c20d00dd2e1e807878874c421010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2014c25cb3df676e643e4e485e013cdce977c80b490f6f71db33d4e5b8c5158f6f831d1b749158fc7e9ee570c2e9d9a161b48a16921c5d9ab56e0aa47e0b0709	1624258712000000	1624863512000000	1687935512000000	1782543512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	327
\\x1d6f1e40f42be5efc26d16f9d722ec50ed1263e34859167afd1eca1a88e0afe9d07c019329f637a9bb75701684745567ed6368bbd54aa664b7159d0abdb7bb6e	\\x0080000397cfed35a28f0a7525e200ceab2187fb07d1d70fb202accb74f33d8828ee0625d86f7ac337372dd9e16074331fe27028c57f1109624b52e5da663e25bbedfca6d55baa00a4b800744dd70b8b7ff67d32a27cacf6aa3a9e9148e6b61b640b692d966526d28366e1f36c8965378df8347ab215551b7943820e411c712b8e7983b1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xce16b7e6e18cb61162f3004d4284c0bb43674b48da8f55549fddec2b394c42a4dd57955267f0cf0853d29e89cae697f476ace584785c31e15f09ab8642a5c108	1610355212000000	1610960012000000	1674032012000000	1768640012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	328
\\x1d175e355998e4b4a87b63d700bc2f7240b15bb45b033557f4cdbc75a2634f077647a5fdb8ea5ac2ef670b1279191774ad5d7e6f18d4d04ef27fcc2dc0f1c09b	\\x00800003e73497619d60706fb6388b4c3aa3d8cc7927e77fdb05da4f3876bbe0b36c31ba7ac14c0592bc5e9c32351fa1ecac90193a2cf12aa0d8fbb413f1c63b8fac0e926a7cd5b682b08a513c826a4c37553d9aaf01b9bf3ec2c09216d7bfb839711e29421149d0d63cf77bafb66f77bd8efa330473a288cc0196bcb21cab09c7c9b227010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2d10a47cee3786d825beb2b20a428ea583180b344450132e1a867aa2ca38f7a898e711f32111e276d282dcbc2b56e0da555d98364da00b2e149a7458df93d50a	1618818212000000	1619423012000000	1682495012000000	1777103012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	329
\\x21ebdfbc778477607f6f164f5959348da661a307af29b532bcd9f66d1cfa681278b1f398ca2072b1798a43243b5619bbb05869ac5f9503f1a14356c5e142dd26	\\x00800003bae6f6ab9687cedbfb2571eef8bc55eb9c9898f35b4ed99b33a56dac9d66132eafac9f12f544401ebbac832cf790a097d905a2d420051b749ddb9ef55912c98b0f3380b2a3f75b5db2cefd365ca8923395b67820da50a3d1904e1c8ad34d74a5cc04ec70ef44a701da5ee230a65a9fe5aefdc2383eb2bd377a057df87a5bd73d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf53809911af013f94af10459f56c70f6e56321b5d3c0692850654fa1644916869bc6795ffc492511581ca9af4d63a58188d50c4b31993d2b75fa9db7114adb0e	1626072212000000	1626677012000000	1689749012000000	1784357012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x248f99f999659f4e93f96b36d8e33fb6244427e2d3d269a84c185450a28ef45fd7ef24e15018e35fc5d24f386fa5f2577492b53a6a4a61b3e120c5f11beb26c3	\\x00800003ab4970d5df6cae13a43d9b388f91940430904ca3346fb10207569352043b7b27234f2d32590e31ee8d3db5b0db9172fdce8b03813f4e43319ab872c32edf85b98684adecf54ab43dbb9995f7bd8c62b6e487db450b27edde5052ea76c8120a1905312622ede7d56c6f328c60a28303bc42b506870f58fbbc8dc7e1a5e4b3d1c5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb446d5c215c30c4735f26f31b22596bccfe80d72c2beef288f50df793dc71127134cb2cef1530676aea6c8589251c2c54b1d1e718b8273617f55c1d99a670104	1630908212000000	1631513012000000	1694585012000000	1789193012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	331
\\x25737f1d2f80958f9886cd59e7ea42d21a0119e7f19b4138a9dbc2256605b5f1a9233ecc8819a0dc455a926526c23053f4cd056d13b04707e3b4f09a32f1f63e	\\x00800003c24c85b1e9534debfe261490eaa90a15b1c513aecdccfcf05bf701ec6dac5808167d1d2c08d24554206e775e3b6522304ac0a314bc6116834e7922e655eea0b4a58365fc3b01e58cf78d03b8f29af1da2417e6ebf712c5a70d7e330c7e51b4309f7a0a5132230133fb24e863f019ac271c93f0f6efb7f4b3183072624bf4186d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x012dd05d003d23469cde727a76af548b688f447f4a6f63495ebec440f8c0a4b8c8799982bc7246c391ab949dc49fd50f273217baadd09e3bec2f9fbfb150a007	1624258712000000	1624863512000000	1687935512000000	1782543512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	332
\\x2e071865731886930977c00fa3bd714bea8bcb1a4071cb259f18d4370026e45273c083d660d5b64d51ace05f8978c86a96527edea4c8587a4600f6db208f58da	\\x00800003a3383779d98e24bde8c06ae99ba77543f98a8198515a9f6a11e91198052143a5cb4e166d5f651180045c1e472276f22e50b574476421c7143ea4af21775f0443306c1e6d26f02444db183f54a30309cb4a2605de4efc265d4351f91d5048dd59acbc8ce4c9e9842664df64bdc7e8343ec4e6ff179b9298228b26713def409cc3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd2617d5c2499c86bf2d53633376fa1ae3cebb2261e193faff5228c21ee4503be544489179cff0e9973667d7e260de5c1c134394591492e5dc63fb4676f27680a	1630908212000000	1631513012000000	1694585012000000	1789193012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	333
\\x30970cbf1391444df8734feb297c4be8cce853a6bc5122b68773cb48b3980a808950ee0eba2936e820c10c79995fe761c85b334daee672309ffb47a26e53ca87	\\x00800003aea1bca37ab91e75d4a5458dd400263bbf769792d5bac224756bc6a39dd6347aa5cf5d64c7e7d80ff3fbb9bd916e450768768bfcc48337865a01ccb30f442f69a2f74157aabbafe94c82e5db4d781188ae90c67914fec6c817400b69c3d845b4d37f2bf0ff2befa30a75d88e0310938b0188d0007d2071a4975d591e84ceeb23010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x07a17b33762576f85c41e1089085bc6a540e65ff7c9b55c47a989df75cf7ee8a3d395a1ffb54143d1510c03e9bd899a08055e49beb1c155fa8628f1d689c7e04	1632721712000000	1633326512000000	1696398512000000	1791006512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	334
\\x32bbe7107d940c96dac861f6eede8f9c59e3f87517a8b11495aa013bdcc4f1ae2d3448fbddb853518a64e7d56b73d3e9a781d4f1a11dce1f0919e349e5898055	\\x00800003dbb366abfe7a15a23771c10a47e207d1ab210ec9cca80be9548eb157d5c7c9f69a1b396813a54e8ac7951583f6ab08ea380f4def07b0789bb4bf77d670d0041e424bbae17922f644dfdd727947fc29a8f1d8478a8f3f5e619ce820b144cae38906960887bedce63fbe680302e437188509d40e09b2c055dadf74dd0eb12459fb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x80a2b2bd06bdb4a8e79ecc4ee3921004aff523176d1e5452a6f2ca8d9dda04495ad7f0be694585d1d16f781dd5fcf6272ce2bca027e9b111b54f7f8d9fc6270b	1614586712000000	1615191512000000	1678263512000000	1772871512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	335
\\x33e71894688ab6eb042f616f455642632e57f5412ee756bd0b3633cf245c739aba6eea9752240384f3039235f22d1068f51cd212fac1392d8fea21aae40b9890	\\x00800003be0896f353d2e12427461b27582d99f8fb03279a7a1b81a47c37c57be780c8365cba65e42ae2292d0cf1ec12fa98d36190d7d97bd91649a1fc102d14253884656fdf056dddd45aefe47b4d622cccfe2e5728d9a34d058f4e9a485e2d95b811aad2fcba678eb1317b4b424c47664ba9881497d44c0fd78b87b1f8129ca73ca5cf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbae76ff13a8800e94a6bc8e7c56bc45c8263be0de8d62a7d0fbd02044bd3bce03318e7aea5d9bf1acc3f19e8491122643e3e8ddceb7fd18faea01d15678b7807	1626676712000000	1627281512000000	1690353512000000	1784961512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	336
\\x34cb8dd0d69cb3cd04f0ce9b7659221d8044fca2224ac0a9eb8bf27b067c5c7414071161969d1e8242d91facc96ad84cb5c0ff4db46e3b5c52d071dda3a925a5	\\x008000039bd394ac71aa0222be55bdc10e34793c6c3d7a051b15a8a0a3b338b2d14af0649397863bf65a10e49e394988ec104e7f01917bb2be1fac1d7b058171f405491bb1985a22d1ec754df4a642959c18707ca094accfbeaf4878d8c0e35ac5a4d3de425a5662b29d3c11c333b3166163c9222346e86a5013ebd334e8f5fc73023ead010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x915fecd33cb60a18f15354e28195ff474520325e71dc301f47ec9df0ed293119ed5cb2dec4c830b705f21b6b9dc7a828fa5d34d76311721c9a9942f1d5525c0d	1618818212000000	1619423012000000	1682495012000000	1777103012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	337
\\x366f21f7f039ae851a179aece568317976544006bc2c98fc0e8e6822cb83ed39a69b8f723824babe20ffc2686032717e4b66cdd3c34bb19c82a7da5eb4d155c7	\\x00800003da9f9e7229c27c167c45249ce018300f8868e23c2e78fa8006fb1b844ddbe12e4c0db893b70878aeb3fb9144921badb25930f29b91238c1203efbcc11d2f90499169368c2176368979aa82ada2fdb26c8fed465ca1b36159e661004cc824d56afbfec539aa8d6a43a8d147f12debf2ee989145c5bb64a36677b6fc3c24187643010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x289445a6a858984bfee468df1311b2d7b179a12d5d7a93c7ee9c0c0d000edd9614c2c08320050af3d2fa1da1f71d9de447a78dc4ad17e0571ed1881030e9b409	1612773212000000	1613378012000000	1676450012000000	1771058012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	338
\\x39f7ac6a62feeafa1257e057d42a1758275072de10de89fce2ca09e146f088fbbe9b3f1ee2fe5fb48c3e14ca7f775733a615886e87692147ae11c0cb21f6642a	\\x00800003deb255ca96f3beefc6abbab6859f0c21ac40601c46015b701af5f33fd930a5a68acdefcb1b3ea6c8ce53f957851773eb136ec1c412a2a9bd646aa17600ddbb0838002af9a8edacb7c0681e7d58cdcc531364ef95d53023b545902e6fa5148c3b1bd7a374ec1f89e91a51abacf8c5f7f8402b8030e609140d657a663e70368217010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa7d89dcc859e03ac457bf0019d2c2c138a33eb2f7f5197bc908309acb7d54b6094f6f122082f2f35cb761ca81b0660ae1f1240b1c232fc744f3b9aea0c01d907	1613377712000000	1613982512000000	1677054512000000	1771662512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	339
\\x3c6f3c0baa2ed9dc46145c989ad74b34e651ea9537b301ad8ee0d685629d219643686400052eb7ef1f8f3880d0a41adfda1abcabb57cb13553a3eb88ef431b88	\\x00800003e7b6981a52e14a43dc2501dbf70e33397b080adbe8e1ebf25cdc62cfa4c094057b6531b2382063cc16349a18e3e1b4eb22e70001323dd19e0263a44eb3cf20d85d6fc410f8f7da2006fe986d5587d26bdd9beb6a74c97c85a4cdcbfab03500faf964ebec4deb30ecd1e00c8d2973249dacf9d6bc04d7c1f07b5738671cfb2c53010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xacb6cd8913ebd30f89113ba4deebd57694c525cd23dcddf247626be3617c56e9917cf9ff5105d0a293f491c5793d7e3b6677a36ece8b70dcbbdf079e6a8cbf0f	1612168712000000	1612773512000000	1675845512000000	1770453512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	340
\\x415b907f8cf04340b4fbfff8670ae9df94ff5e8614f7714e160441f2fb39fa2077d9a9d91db6c2f7c8bb1deeb939d199c7bc43ea4fe57a57c3a937c10857159e	\\x00800003b92adc361eff13585d3d9934c1159fc6b5c6a3560938d78d2bcaead6a8056760ab7bea2dcb1f255e809420e5683de4e4e1c4c13ce04e2fcdf5a4c23bbcef895eaa660b77045bbfeaa9e119ee06e4e74a18bee2ac9cf189eff8fc8bab8ff3cf106e2bb212fa20f8a529b7ddf9525bd3bb1c932599374768647c6d25dc251e71fb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe5d2ac5f7756d1c9a1fd415206f9f5075026acefd5e8d5e64f9f5e1e9e8a274161bd4af7353b93f30fe8bf15cdde4c7a896bd59f22b3487f3a20af8eeab60206	1639975712000000	1640580512000000	1703652512000000	1798260512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	341
\\x4243e46deeff6fa6e95cbbc3c8073a28facaa586d79c402b749489b16c1fc3ab8f5f2b6960bb96bdd4b800596bf9ec4932bc5f06312726f23650852e5223b5e0	\\x00800003c6554c43944d07009897b13f5e5daddc8871659ebf2230f0182051f79fe94c08b623dfd321d818157f337006c2f95e3e65d98a96736196dd033eb264c7f3e5b8d8c54baf9fb57cc021864f925954cc4526eeac7b8ca4bdce4b10cee6c86090f45e586c521414a0986825fdac2f5bf5f5ebf65762aa269dfce45c6b313fac4995010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe65a97a1f22574017eda89761ed3163159db654fbb5c3f5946d76e56aa2395a742897231052a2c14da5d6eabd1485c36b560851081667a3252e9f85945096105	1620027212000000	1620632012000000	1683704012000000	1778312012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	342
\\x4903bda315c35c1e53fea7428a12a041d9b5fba22137f6d3163721503f27220d60c28bec44f38d0ac8ddd957a9d0684a6fddfa6a622a78fc170c4b60709a0dac	\\x00800003e448e3d967519b59f6da773599a9b1c7f2dc22b3bf61ae355817630ffa702f9f423a10f7f3d891d641b4f1d6f78c4e030f544986056b76f0f2ea1da46cba63cc4bda1c659ba0f605841ebf01f6042255af9a313f3528581df5b9042d9763636b5eea047862bbf238236f1972d9e3fc035cae5108ad2721cb39af4fa796633085010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf95ccfd64688a1a7efb74b0dc9ab5aa701ff5e1bdf1b79c20f399eeeded09cd0bef203b43ed5bd3b06e365c63d9407c5aa66f3ab877b39cfd18211c5948bf402	1624863212000000	1625468012000000	1688540012000000	1783148012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	343
\\x492f0d087e1ceccf3d3288285d4baaab72649f81be70e482746183c3d2befa0072b0a6d405c65a412e1fc8c875d52b6949ec979e736e19882e319999bd41518c	\\x00800003e98129ebb74e55d9b0b0c515e2d4e1bf9b96f5887ddf2fccb4840a569396679e89a38e3148b5dcb87bfc266592eeaed242b7cf60b86073b5cd021ddc383e24dc774f7adbe83765e2e5c6ed40b97f0a00aeada7ddac4613b87e6b071631856a1cacb6351447b004529b4c11cac87a329ce4feeb98ba3c7e53cd182655abfff963010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xac1729aa9674f99dafdc6544bbd3602eff56db46c159908aafa4f1f6d905b43f59cdee54e394b3f8307556f7e54dd40158c25b9567b8323162c53299db46c60a	1617609212000000	1618214012000000	1681286012000000	1775894012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	344
\\x4dbb01479a2080e1f11be42365c8802c5a4785eb1a2a362fafec12f7c5fa8a59909aa85d10a089749938b6afa3f31bb91cbf6171033f0b302f1e1e7e27a0ac6c	\\x00800003b06b41eb39597ee66154413f2165bd06092fd807fc485065aac6832fd92dd0fbdaf8d13d9729cdc5224cc40ce553cdc4174ce75a3408aed6b32007580406e33b046bc5d8d9f5ef8fa0e1695516ff2796154e2b9f793df5b44ec94e7af86bf9e5bdcf3509a5f5a8a3d26714d92a7d19561ced1779c7659846688906fb1b75224b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x89f5733eb004b2fa91ad005b38740edd91c961cbcb9c2c24a5b8bd0f65afa1d4b6e07f3ef48d100eefbeba570829b5aeeb60ad9eb08927cd03cef72565de7c0f	1617004712000000	1617609512000000	1680681512000000	1775289512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	345
\\x4e8fc667321e70b6c8deb05f945defa0caa589ab86a1f9d375d16c0fac1e2a5fc49df9c5fd7bd6d15fd710580d01efd8667aaaf98fd86deb06040678b8fa2d33	\\x00800003d2e922c5c70e9a3be9839adf9afdfe691a8830a8d77299ee5eb0c0a43925e4abe61fe87ac836a754e240fbde20074040f3a7f2df0b76c8e32e7dc78ecec8b766d6df31f7ce6c3b33e8ad5bb3e8353c9a38ba8c11a4f90a4c6845b1f1d1541b2c9257a4b1ff56e838db46affcac1d5e201c32b267eb64b944224642484377176f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x649ac90a1ce1345cc7bb4b34cc568cc65cd4bfa18e79e36d5ca62ab711e6ba41fd22e6a2b2ed0a8d9bc762b435b035b13ba34ed728a797d6773fca5135182300	1613982212000000	1614587012000000	1677659012000000	1772267012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	346
\\x51a3b51967e5aed79b632652dc88064cdccbce22918e526a6f80802ade245ed88358f3e9d7387bd4fdb8a57fd1cca1a31379eb6730d63d66cdefa8d3ca7cdd50	\\x00800003e96ef7e741ce3ce6c46c597ff1e3af0327ecaafe5a2214a0dc0659142dff4a7660f00acf81b8d5323442a5e748cb64b7b749fd9d8fcc7d60c797dabeac0e7c91bd0fa2d78a852c26924065c23f986a2f4b5067fe3145ada6b572dd5703a7bdf5df71c9ffb76f01e4a1b51833dd83a85ff15eaaa8c4088531b6768820f588ec43010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2245c19aa2bec171925ceba252ae6f3093c86ba955bd671a7ca3e606a2e72c79c4a126c38a37cc6d4012bd39336b57f21375f9dad8de304e2cdb8eddd696aa0f	1635744212000000	1636349012000000	1699421012000000	1794029012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	347
\\x587b87a96c63ba8d4adf1b4af271583d410a9549def3f9b871ac698a7a8883788dfcad46b96efcfea9a305ab90956d049d587efb390364611ea2c0573d9ce8dd	\\x00800003b7cfd5af4f3d65b29ef22395e211f34faa94a3c0eb632b592f943aebb29e88496fc21670cbe31931e45b5d3b05ba2580e7ba1ef15fa6997cca8dc27231905ae498ae4bd1a82484c7816cf98c16ee0374fc9aa8d9294f4acbf74b2cd549eeef1518af1f5410ba3b807a736c49683241db2b7c3fcb9513a187538e75a8acbb23b9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4fc723d86b590effde491f40be095f28fcdd78d23e6b4c30106e6c620c00b03ceb3abab7ed2c5fb2302b7b183a60a118855be0e5aa325a9a1036369758d80309	1628490212000000	1629095012000000	1692167012000000	1786775012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	348
\\x59fb4bc345bd109275a65a6b68440743b0ca6bb94749d502b0715a6a21f9249b879866cb439d83e54bd4218252065c7470310bd1a0a8352b6bc3cb772f2ca82b	\\x00800003c89fd24a6431292c9ac5558c4a66f2bcba5f5738569c2f9d841cb020f8b74a4aeb67653e83612efe143e57e81af6c67e929eb94755f42b3344b7e993081698ad0e88b329a2731811d690237ca4eb8d953cf2b564027aecec68c9dc0623d96c52b9ad510c9f287c2fe1ec6325c408f8417b68f6d5726d9f81afa3961779df5ceb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x214e16d86e04f9119d7659fd710c5b58e0c4c899db052dfe74ada0fec18614a027ab330b5509a56aeebe59b4f3fb6f557a845dcd46b73e912d4010e8094fc405	1620631712000000	1621236512000000	1684308512000000	1778916512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	349
\\x5ae37025e2b34bc9ca20e675f51caaa011771d75669387faa141f08fbf031a60ba2eafc3180d9c77e6af30cbabeb39af7e63d373655c517bcd35dbf2f1f60a69	\\x00800003c3aecfefbf0aacfeae334af6a43b06c6eff131c4b8e15b4618f1d21f0d5233c530f3b91a38305dbead966eaa2c3d46592bff9807d3a10dde5cb8832c45753247798a1c6a8cb38237dad7176a04c28c332af700a21a675d4871bcc7d64436d4c30199dd7fe6a9028a2606431db0b553c7b85037396f568446259e79fbc97c5185010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7fde82b8337f486e8f1a48be108c4136face62772bb6a7100011716687395962e0d21cf305538c37d956934973054995aa3b7a9440d9d82eea2e76559a5e210d	1623049712000000	1623654512000000	1686726512000000	1781334512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	350
\\x5b8b50bb23e7a9de680ee778abb719dafe33142de266706a45b68f4e644cad53c8d162f6debfad670bb863a9b177d2481ca249d742173ddecdb02c8a939ae560	\\x00800003bbfee55a61839f3536c79be5621b4f514f72a2a996209df6a3c1b5c097145f3acd37688326a440ec4992ca72ca38e16b47d1ad0d4c3aae7ee00937642f5a50fd18602bb09cfee3bd97ae584bcb33abc92dff3ae6fb5f690ae6c8de248672857853312b97daccc57f4937b23d9be707aad8431dc82015bef0749d1fd2f18fc5d7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdc5c431fd1d5310c572ee6b6bf7e5571593b71ea30733f88533ff4b8d7e164bc56a53dcc89e29e36002efeb93bb24b13442ac1e0b8b8ae866ef9d26807846009	1636953212000000	1637558012000000	1700630012000000	1795238012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	351
\\x5f53f3eb285d77da1d58933de3ec005adcc35e89f24d609b81a0efb1d2f9ffda0bd856588b9d40b64def853b701bc340615f0df387abb337605b6d12db9b169a	\\x00800003b805d0764be0de1f63e5252b1ce429c042d3a891dc9ce351de4c2504208b2ed799f86fde3ea225398720c0b8acc3e1f9c101d26ec3cf6014dc1261a3756bd11f660c681efe0dccda461c068e34284a6922903d85be1f10bf4098b7da3e20d529702002102677f1eb790b3d6769b1e23321a3a94c283b3614917c7cf19e18e015010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa44a3ceffdd8f2cdacc955c10f9513788a8d66025573623bcf7d8c68204eb61c1025cb51ce6d9187a4315c154cccfd72c2aa70e3844389484bbe99a83b871709	1633930712000000	1634535512000000	1697607512000000	1792215512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	352
\\x6293b513bc296c22bcf727cb637e937ccba7501919f8299736c07bc2e1ac25d223aba8c67c089b105c3235304f7b5b0bc903378bb1f73dc158e8466f445710cc	\\x00800003bed32feba616ba0f335f178c39f8a137a1429e3e63771564b4051ac454175b926c54c16c3c12ec102ce84354b6ba72c87d645116ad5ecebc0d692318aece9cf8547c6a416247f07fcd88df14397a7b99668f5058f87b6a1401574abe6f4d1c60b4c708efc8385b124f8f147fd8980ec04a5f0cd90bb9b2a449710a4ea19b29cf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9eb3114c13a1fa2175cfed164603faa52f29a5d91d8ae87ac9473304417708d5f31e254585b8671dd80ef19e85db160ea8b5c8611994aef61d8eec6731650809	1641184712000000	1641789512000000	1704861512000000	1799469512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	353
\\x66ab925c666c35db6b178c3e8135b0fe9390eff3ae4005e84ff9e0dfa743e70e692be5960c4f28b1a21dd8d24696d8a84697517289cd199ed6b7dcc2eedc62bb	\\x00800003ee644ce100caf22bcf9ac32326095de3a39dbde509a24b30f4f8967e554298c3413e7a181ecc947bd913ebffb4c2631fffe136826c29399c2b71ddd321d01226dfae69dbf33fa89d2eb150a06e4e466eecb41982aebec9655015f4c4919857208a5ed7cd29303d0eb36b7d7b95463abe40552158eefece39265c522e15bae2e7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x847c2fb4d8f1f1ba584776e18a0a97c52db5e4afbb12905ae737765214eb1d568d573930e36164a16b5e5052ef4005f99b9e2bac3c6f5dc23b059ffad5fbfe05	1633326212000000	1633931012000000	1697003012000000	1791611012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	354
\\x6903fe6c81f76ab52aa50b9a11fd45a3c6e22420a2dec7ba964ed9fc9b1aba17ce31da135f3b8edff9ab0c4dc2f3a14f1d22eab417196d8ec21cb897396fd15b	\\x00800003b94484edcce62219c13a4e43bd329451fb64e827757d59b3727270ea4b26415e772d3d8b02184a4abb5dd84ac2fa9be17913e2477619f0a66695ae31c8c93ad197b14cb6607e98d0d99adc18fef7b3867f6595009d28593e7df475d5afaa4f9861b229979bf3f0798d82e5e43ec2ea71da43e7be8a02e44dbdaa7b85cbecfbbf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xac01bf8b050e88ddc4c25d5ff4b7bc8e5738a4691cb841a6808f3a78d816f516be82303affafa5d466599d3e1b3131a0723c1d2c6c3622e751b0c59081ffd907	1639371212000000	1639976012000000	1703048012000000	1797656012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	355
\\x6a63b586a27a99adb12f79435c44bb0dc9b51eb428b614de6979ac9f7546b17b03b1d70fb42bad0b3800536def0b596147add6ceec342774bc189282d4375659	\\x00800003a0737b822ea9e74f312f7cbcb05a089da425f85e0fbb7f3594fd8bc785fb0e86f5c5cbcb652c2ba7bfeea0ae275013f057141104bc21f5e2bd8e170c36b335a4caeacd2186abc8bdc3c29a57abd535638e49e3c2c590613218e9b6f0c4d96f4fad58a130cd8b0e1726114ad71d57cd8c78403044cc91407c3713d2c61e8a4de7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x0a5ac8d144b59e56e4e617400d51668c2e2ab545a40a30fc1aa358c6dee415f3fd127282e3a64d5dbe868d7bbe2ad2811f783a7423c447e9fe8815b6766e3f0a	1630303712000000	1630908512000000	1693980512000000	1788588512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	356
\\x6d2f2a3142c69da27ae44338b939279597e7e7463d6d47cd7d7cbaa696b622885a057a810732d02513111b93d667c503dfcdd96cc292b81d820d848259dc92bd	\\x00800003f632b74fdf001db16ebb21c73d8ff9ddce8f3ab018e7df35494c01970a6825ed78b214c8e2cd278643371bcbb3d61def962ab6d7830c6faed256717b6c2584a1f40695562cca69adc4e8103bec2bdd2fafbf55120f0257680c6220a4a3f13c99b97df975d460c33ea0e69e55a73b0e8b5b3165e9a8a39af20c316b94a0f7269b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x852d7ae5c7089edd5e61cd2ab9f0d034077427a7eb4561239e9db6c1e09cea4a4cd3714712a4ea8878b9f9df42cea8e8314e5c557bddd59e4145b350f576c704	1620027212000000	1620632012000000	1683704012000000	1778312012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	357
\\x6daf7061f4e7d7f54d396edbd5b68562fc5d249ec0880942ddc0da58047766320ee2847b6e21c177d5cb3e53216cf565e625e4663ee7f57c06c7610c8e48f630	\\x00800003bfc5ccc401af4fd22db26d65f6a400d8d320f759b25d44a3b3728774c4372ad48df4812c6840e1ec4f781bf9c4de6189b75f1e62e592783c3b2d7b0b81f545553610ef8a8cd550123760b6cee05f03c7ea48d7050a3c246f1020b6a6f6dbba9268cb920606ac9ee07f5f701df192631a4da98d924b65dbae1a82744ac3a7a5c9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc37d282add818c2a246a69a78761baef91c3be0c42655fb15dc5dc0ad759fe780be142d355444311860609b958cf984f4411f90de239841961641f1fd7de0505	1621840712000000	1622445512000000	1685517512000000	1780125512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	358
\\x6d17c8e00a144f0944def0f1d1d5130eec098dbb6aef12bcd773d272023d83f6c9e07db8d1582aee60b23b62891cae9a223f3ccc82288dc751c0ebf244ef813f	\\x00800003d0a8b54b6193730c7c86ea3c90e6dc2b78ef44f4161cf706aa6e671634957c86e1c17db0c1e4716b686a2f76c0095c49b6c72f5720c18b6e54fddcd86da169a42d4546dfccc48db210057978676d5201230775fbdb5ff3214754e5490759846954bfef1537a229c68dec320f419a8c51276ce8843f01cfb3e34201ed2eda8137010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3fee121a404b3426de1f8e43d1b872186ac8b4410590e4b1dbedd21da7afcfad814bf9b46511a4bd7bb966e7fdb0f2179a0e8abea914ebbb44395bc5b6e8bb0d	1628490212000000	1629095012000000	1692167012000000	1786775012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	359
\\x6e576f0ea0bb6c5b24435e7d66576a92beefe4366886f186461b8cd83a435beee5b3ece49ee1dbd9195479fa4c06ea738d598a9e9aa41ccafc0f7e0ca58b7ca5	\\x00800003b0665d26f28154ea997d40b99a8a7c501965f81af7d779d4e71123be4581d2adea16c3825649a4c6d81c07a9a96336faddc77f08a6e6ff1b59c41aa8d6a0204ce8d3203de62173bd9e0e91ec817573b134c479b9c30b3d08fdab661be7cdfe3bdca74e5c0ea04d883f28a96b9269f0cd2ece8e6132e315f3507f7fdb3a9e2e57010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf0f97ef879369c830521e8a887214c14e5cfa7b1384ac5de8f5a22dc012c52d449c7d7be02b45f73eae9eb34cfc8e0ece3c135e05eca9227c550076e4ebcae0c	1631512712000000	1632117512000000	1695189512000000	1789797512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	360
\\x6f53a91ad6520c3a6d1429047c28f3115aade6cacf4e249debd45fef7e5bce31f64579766fec84fe462b1e4fdfcad4eb8e5804724f834e49caccefd59f7870b5	\\x00800003c0a256d9f7625f07cc5a20467dfd6c7aab3fd86ac70eeb76bca4d3237b5dfcb2303c8704027611b3425f22494d5f6b9f079eb1f2f3324320603103c478fd68e3acc59930f152191a6486c2c726691b1f89f8886b4adc2e5f5074a574393d0a018f679fa26103381ddb77495b0e26fc9c0029be8a1273dc6313eca4345c5f4327010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x668e52c32f7e799e465e066d00727290a5355830ecc61bdb50ba9e1a49313ee5fb221f42b0a34359e3e87a31046fdbcb06943c851c8cf6757e2a1c404b8eb205	1610959712000000	1611564512000000	1674636512000000	1769244512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	361
\\x7523f364e10e85040f2489d4b563f439e2eb2913b9f39fbaf7f6bedf4fe9ac3c590bbd676b80ff6b73bdb8fa96a66ee5604f1b0f4a94bc1b9e37ae8f45bfd84a	\\x00800003b1abc49875a05c750320cb99195cf58b0e8298c27830f91598afacb1d9063b0cad800e9e3712bdbde9b9b70fb8f27f54fdcdd6fdf006f694844f68eecca9ecf14c8091dc78613feea502aacd375ee85b6382b8c7159d0e68bc3b6dcd763acfa8ac310d398f436f685f6a45ebb954576a11411116d1f9e639ae67cb941a9af143010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbab07d654b7fed0e51bf849d8d34ef6a5d4f0312c35b9253b07ea999e01fa969a04896c15a629a173a91d418222022f7c303d7ae336ab9eca8e5dcdf928c400a	1633326212000000	1633931012000000	1697003012000000	1791611012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	362
\\x787fac805e286f9d7fc6c6a3300eab1303f30b0e8b64fd81788ab5192cb92fb005159740c86d5e0f94b3bd746ef64fece90e65f568733f8b20aed7f3cdc11bd6	\\x00800003bcba2ef8adbd9951c83ccf285a6773620a320c9f8dfedb9d9409ed17b3efec11b68e0845310923a56265eb3632a212bddfe9f37ae97fa42368aa11a1d0ed94bb8161565bca64ac96465882989b3cfdb97aca39f156d9d8c4ecc0303f4acafd2c1a04796a8b189f4941d1b18801e65d01631f0d148946dfd00f000e80173c9883010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcef2e1b6b0017cfa23459e15d07f58285c89f88a6265289ded475942be63ecd0b2baa1e4cc765aa519596027fdc445cf7eed458177fdca745544e597dfada007	1629094712000000	1629699512000000	1692771512000000	1787379512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x7b0f2e9e3cf53f48c3902e24d17653c37844bf9527a9e55da79aedee1a9aca3179b8fcd7770baafc7b4b2648c962d52670b9d43035c0ec76d775014993fb5413	\\x00800003e0bad036fe77ef8dbd005e047d36b33febe92c72fb756173f8994a5aae4542f44c21b8c2e4b42cb9b0ab5dbb4e05c0d183323da695be28beec4178e8fb4ed84008e315343eef728e646b7f01972178d4fbac8b04d88db094a2052df86e706f8d00869506ca37e6bd1a36fc496528a860cbe26e6f7b9e57458272b6c5ce44fa09010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5b67753abc20acfcddf270665167f9e2eac502b4ca01886fcd243564a11beb44589fab1b454e01a9af8f89dba22a5a7a0e9975254969661114a61f22e1e0b20d	1641789212000000	1642394012000000	1705466012000000	1800074012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	364
\\x7c972a8bf24e2c2d921f254a48fbc081bbae1bdd401f35bd7ceb76ce4b83c2b5c729e8b55044364a7b2473a5adbe1180bd856306ac67180e1c0d842bd2408198	\\x00800003cdcb8d164fc04dcc9994b35ad757f063ea488c561edbab0dd9e29db597708caa31c86070883cbd13b81d3664c42574f68b13dc0cb7ce31fc06e47fa40571f076a37cbb50c1df0186f1eeb271d77d4368c6e989c965969265a57ad2c6ff509c4471c4564ad34643544169ea8d4e667831674868420454cf503611ada6c5e21fd5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x46a391716fa564c038335083f8deb95fe1ba1e981985cc49feebaec06f63ac15714d7a79e302f30f6e0f43acc329037f1e00680cd385c3b2c91c81a5d67ba60f	1615795712000000	1616400512000000	1679472512000000	1774080512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	365
\\x7c4f4980c4322291c0bf07339eb472accabeedefce27712b2e19d542fdcb481e2c0452e32fb641c43519b69fe96db9b1caacf0880a27e4b692484037b86f7180	\\x00800003b5c0a6d92cfe456f6ebec04848b9176622265012ee1b4de7ae9ae709491c4577a6bb0675d61f2b200ddcbf7b01c70a0b96654f18634c85ff069397e6f5b352b44ed158c2dfc0533c1e1aed00d42d1d5d65564850f7208ca6546920415e65702d8e595d5d10ad105b9e9e242f09c5fda5a76a99631c1f9a6b8e10e119fab19813010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x4b5f53c4d3ce713714ab151f46c7e4c001d116e564e0f02a8c59d9a5a4af4658ef1f41222b2a36df7c5ed16661469b82f9c7f61894c359097e502b3820551607	1613982212000000	1614587012000000	1677659012000000	1772267012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	366
\\x7d6f24ca6b9af669e86e5e68c1cfcaf30a43dd0141e5f03a2210e79d0e50ad24d988bbb18495bcde83263253546b9637d16e5133c1d9fd82191af639252b9d3d	\\x00800003f1c7ce900186049759b6d51b6ebef19171653205af724ec1a8eeeeaa61e7fea85c25a8536dc5e72d96a6ac47648a32308f96251ed3128302ce99bce8c1a943853a93307bc2bc29dfa2612adf315e838eacbdfd7925f4104a319b8b700bead19b05d45e62e223612869055b3dae241d9ada70cce79b78eee2ccab905304753315010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x520cafb39faa01e6933c7ded4cfdd9d0060680b2aaa3c41c51ab447fdda6f6529929e13dc58c5c6c4130334766701a0b5ad69a4a17058c02531b8b7ece056c01	1626072212000000	1626677012000000	1689749012000000	1784357012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	367
\\x7f930ce16aed0972da69c7df796f7316839ac92e65be4324f75e19145708f4c88db4ff344e7017677cd8c0fedbe56f31cd511469c7e147438f3a9a8bb958ee97	\\x00800003b0612e1754dc37a0728419f89333578147e63b04ece8ad05b281f3c00b45846034a11248c355a74f22ec52960f914d1c9fbd92ce2f74a8e4d249a3fdd72d9492ce91f7bdfa8b018ebab4a8245234e5cacd7aa10208dab15338f457f799b18b5109613331e3047a28ec463f83ff91ba82ece71e0e6653e778269838092600885b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xaff71c2b271c5763eeb66f12b8fc4606730ebbbc4acfd78f7b92e8e28f329c673fa6abc0ce8d53cffc94e5bcda9765464c327b383f29ea6f76ca7f8d8448b602	1613377712000000	1613982512000000	1677054512000000	1771662512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	368
\\x7f0b0ffe2432b2ccb0936a2710781651c4eb153c5305036041440d16e6ddd6c125753f21e76c246146f28e8d9c3884bcb7bf9dd1c372240f6059504ca76bfe17	\\x00800003bdb18fe15d2b618434caadfa6a254aaea9b7aef3b8dc5397988d581118e92ea7a02fdcff9ebd5c17ca23efea1144307b6334754a8f9be61250813e0b9f4c6e6b16189388d92e7288ccb23e77fb5811a09c7ef707bf026054d8e1dac3acb74fb877e12bc5fab6c67b4dc1cf3de0c2ef8da76afb6f2177b69d6f257b9432472dfd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb2d268d4fd5e64a2ab55a0c43db93d3087283960c136e6a1e80d8ce0714f4defd85947c3ce00de47835a6b30fe07a965e96b8bd772361349b1d46b47c71fcf03	1616400212000000	1617005012000000	1680077012000000	1774685012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	369
\\x83873e9a35b46d0c3dfd484c4b6bf6cb95a6b975d62515eb7b7b0a5a18819d18d332a3235fa6442aec95f75542e0ce327c942deaa0a042296c07ddb0aaad6f30	\\x00800003dd58dd69e4db7dff4a6c3324fd4b03bb4a7f819d14cc50d87bf9a5610b00c706e7b113a09abe47c6e377a72aee6e5e6083683248bd3ab15e140b7cd08ac03ab052cb2da0c43a6bcf3c79a2e196a2484a21256257cff442b821f01f482663cd411f6b3f24167a635ecd58652407a3e21361bfdf605537cf87cadb5e7bbb5e73a1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2448bbe00d09554e7b50a5f6069de05ba8c6644bd2ae67a313e964415e6780ff95ba45a297d3dd1ed0bf981ac678960e71b884de5501a1d7e95b6ea65d9fe409	1637557712000000	1638162512000000	1701234512000000	1795842512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	370
\\x844be0be5295ddd21b7f40dba6e271ef3585396511d3beaa23e7f42f082e70dc9ca7994592ca138c106f8c8de9d1c4d7b32e0df150459b4c8596e3652acc10c1	\\x008000039346949f1dbd95606bfbf2d9172b696f3deddf575cbb20b7fc243e79064719e71f8b66688dec7ae25152db15b2922ccc3670cf54f51f6020dbd027432bac2d191db62c05d27e4901727857bfdb8ea1541902b7016c9b72c26652dffb92b04885d48786da1feed5ca8b5d741944eb212f99647ae3acac9ee07cfc6c6d6a38a297010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa3aa63ad0714bcf039988857fa6a2cbf720d80d1a0991ec11bccf86c081140398fbe1657c3d8127225b6bcf1fd5d6c33763fc7376b9f7f9ce1fcbc0f58dd0701	1627885712000000	1628490512000000	1691562512000000	1786170512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	371
\\x86c701a860b87e845e914c5d75998301bdbda263f734c4f05f03d172b1baf48d67b249e58a12acfbcb373d02c405f77ec4ade2f81d9d400cd69925e3152a6559	\\x00800003b5fa1b6995fc0c27df6db00fbb305d09662915ab5a6c8ec88d917176f370e9178fb395f92e730ad60cc0abd15d11f97b4a431d769de5665e11893b41000ebd50fd829e7e9955a3a72c0c298efc671a9c880749a6ce7d00a59faf3bdbf1fe729809a9542e49a6058786cc71390bc0d6a919760fc6dbfb9d11018a5aba8c6dd88d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x426f34ae058a44c7e6ba7ab9134d2fc410aaab92128a1e94c86c4450a5979c2fd04417121e19d7d61b40ada44216c07507a7d3694ebab8ee041405f6a2c4fc08	1632117212000000	1632722012000000	1695794012000000	1790402012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	372
\\x8733939545512cc962bb03ff8be4598e613bec5dcda5d39975df3f17a57b08947a78698b5cd7a775195618286ac157a9532605d8f5738720ec9094cc3049da3e	\\x00800003e5dc5ebef1823ea72c3d672f69014bc187e07d4e34d4adfa5a62ae253a5d5df85837ab8309b5182e8b8369d180622003e19511e1505aae35db3845d8c9e5f0f2bc2ed71e23a128aeebdd1c121300d79a81760122bc29647c36cc08ec7ba47c870ce4356be3ad865d63aa8242093fe7296f205c38c548ec8c83ba28840564f1b9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x965bcff5fe3833b822e6c21937eeac646140bb394495abe2214baeac5e47c7f47a308e55b742acd0ba3bbe2cfb0b7983813ddaa88d61165c16d6a8447ad7cc08	1626676712000000	1627281512000000	1690353512000000	1784961512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	373
\\x87df0bb3be9f3dff013c77346628519409bf87eb1a9cd0f1f88b32396276842032ed224fdd48be2d003166c4e205a290759a72bb5dafb3bc22d7d04c7dcd2b25	\\x00800003b57e6942d6676b56e2a87e50870a85f037229be26a02d3f65532befd1735d3e7312cbf9b8b2a9dbb8e2699df1bb6ae8d2978eb3dccd73b0722ab9ed351feebd1dc10ee2c157cbb7637d08d14526dd4f44f8cee371277ba79a3ddc822b4231cd577ef5cd80b340244aaf564462fd14f62ca7f2674feb019f9dc1a49cad11a9103010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe461e72266fe9e1a2bdd8a569f2b5f09c6a2a24541033badf8c674f31f8b78810919dd7a398e916a07b00da1b12bf58c1b2c8a07d340170829190a04be819100	1637557712000000	1638162512000000	1701234512000000	1795842512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	374
\\x8bfbd6532f657c4711db1f8a95b78f3bcc2a3971362c69ba4dbd4439841a4cd1a0ef0d734c3e21dfec7821c220feedf96adc48a19382a6c3a1c73b08a2a67f6f	\\x00800003ced6b4d89381d574069531ba6a6a39c14d5501cde20d02a431633aacf6a753d6eb7010c29e4d099b37080ca72db97e7f8e6a4b0f7d1c5ddebc52771ae408c64284dc51a2dec18053aa267a98c56c8cd558f912ee7dd119c73b44bbe89b1950871c51586848a6037ce5f67c52548a5f31adbd4c8568bdc20ea1c1472735e35135010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8cea090b15c0ddaf3e42d540d03d0a75f15746d21e5219c7e0d7d4c58a9ac0701d5a038551a61b07e4e471be00c8e23908bbe9276eca32c703a378b35699d509	1634535212000000	1635140012000000	1698212012000000	1792820012000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	375
\\x8cfbc4a89d41c1885350db1f4109a5a0a3c9e6e7ae7bc0767be9f0b6013ef4f0ecb75e75d80ede09d7b9b77d64b5ced470fe39d2706a958621c67067814c6d21	\\x00800003c4508e4944a32b155f097673e2ff3577e8174fa59ffa2d0d51f06d01a2edfbe75c3a364c4a9d5ea9687087fa6ff240d43d52f671d7a664af4071c8d0e2315f481297bf4b61e3d9e0dec0d7eb7ea163c690dc4b22f736069c38a0de777a0f5d2aad00f49038e564ddb72c791799d7939134d4a65831e6113f4c7a4d1aae1ececf010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd1858d35fb5182c2e7db80c1e3f34936271fff3e5bbc8d7058b086d9a94d90aff8fb0013d38c9e5e98b4f9d3c61202a51b1ccab64e67a42ab2431dca8c1d050d	1610959712000000	1611564512000000	1674636512000000	1769244512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	376
\\x8d93b71eebff8ddfc50ab36a07f508570c8827a19ca823672f68524e5c21ba94c7f180cca19309101b07dceb3ba50a2f77eee9be1bc7ee6cf12c8cba9a6cf083	\\x00800003d2cd55e2e64e936f76cef97413dfa3b659c3d2ed1437956bf6aa3058988f5b814dc91501294b5e61e44555034ddf52f78289a78f9c653062f63ec0b648a68ed54bf097de876595bd564892c73fb062f660c1743e4adffbcc397ab864076ceb8ed95251dd99e6ef569a3fa253b01f2cca5e2d8a86629d7c05b595f19c33c0d25f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x94f339ac9048801b40771c36d9d81f361b67221f92d9f39bf8c2a9f0267d109c6dd301a22ede3951c88d0961492128d521d0b1d064ed084eedb615567f961408	1638162212000000	1638767012000000	1701839012000000	1796447012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	377
\\x8d27200d4b0dffad18c0d06dd4f48f1e2a52f72458c97a23e847585c996806c40bcfbd4198a2de78bd53f9024c3c3ad9298725c13e85a2b1e88a1adf9df03bc6	\\x00800003d159c9bd5b04c19263260e7c874e7f68f1aa244da16514591655207103f2c2b434f963c0096050c1bfe0678c186921389ca32cc25423f632703d8dc6e930ccfe513b312641e7735d9983c1e87d4b8d0d07e209461b587669150bed4f10c59d4c991428e460d1246d2c00882a87cf81973304cd057f8b7c5763d0e87f38c7727b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa4f70b6060138eaed230fee4364c5ec55922fdf36146e88cd1696d2446ee9b164a243553f3360bf8e9ed6b558a6ae9565beea2631f5e6d7919d6ac4d7e61ad05	1624863212000000	1625468012000000	1688540012000000	1783148012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	378
\\x903354eba947926d4b7a228b1c776bdc7e33b2ebda61d9d29e9744427d52aae2eb8a7db3f35c36b64bba9a166b086742db298d7dbac012d3c113d413bcd680a2	\\x00800003d8e1812b252166426c528eb4e5c586775a0c50e2650feb92e8eafdad814d0e8cab9a2b31463b3390480ad9b927b9a8b7b16c75f7ef48e065024b684b8d52c567d9a671f76fd4c0e204f02dde09d04fe855248608f93ca167e1d4b2c595d12b3c0a200b1e00d61bc0e12cb4799cf503f8b3aad9c4fcbfa2fce9a82079304addc5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x87044cfb2262a8c14740583432a8c35cf3a4655afe982dc81f29398341b19154b628578eea7ddbc8c2e14ca2b8224f72732f0ba24117908fca1a00b3d47a9c03	1629699212000000	1630304012000000	1693376012000000	1787984012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	379
\\x9353c2bc0844bf6c0fe883b3cdaf6498fdb5a5e4c6d897cb6ded5768f5dff7e467367d6f73d381e0dc9506333fc42686c620cb8ee0c8d217ad2ff06520861f2b	\\x00800003e27a3fac2950e03d99bc342f6e41ac3ae1787ab5450e960aa280e381995ef311a07c517641afcbc91abf223c8a60ba8724df9091556311522be1653517d1fb6c45d6af5e379a71fcb6d14c6eee8133b7806580d1c5d44eb8b3e8f8f4134f3eeb033d4aeb85e9e00e93e6a7530b2c4279238453dad0867e4a45c249634e7518ad010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5d7a60f0914dd312810bd860622ff3b9e576f2c94be40979d0d0f6fe6ffea359d775ee39c4f3de3daa68f508745d0d0b5498423daea4d33aa8140aa7b7d4090e	1620631712000000	1621236512000000	1684308512000000	1778916512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	380
\\x976b1867c1e76f6ca7b08c57b4c1c22889c3f1ed6afd1231f9058c8da1f3e0a1a49cc6418a918bcd4f2987984e4201d5613d55cca944e9a2c13bd2ef7b7cb8a5	\\x00800003b2204cdd6e37647303dd3be9188936f3162f382aa0f0a1d89756f8d30403e23c2a267f3ccd12613f05b3bbc5079579fe9dbbb0f99235d35dc622e4c0bd180c3fb3cc67b5156c28fed6a08451978c22f6b15fb773a84df3c981fbf0ce9975db8f56d9175b7ce70649d1b9f7ab2a8c8fc3e98f58dd94b00e48eab8878eeda210b9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfaae1ebc9db1c5aef6c411b3207be157f9abfb0691c31b307e439582c093a5e99216dbdd2f12c3113c64770fd8784a6d8df4a82689562a57d4c25ae612eaff05	1635744212000000	1636349012000000	1699421012000000	1794029012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	381
\\x991774c0cb5c9d0693ff8de462bb96529f323cde083fbc366b1c7eb7406c81206187540a1e0f4d2fadd020c8e1eee332976deeb0b8cf2f75b5f3aee4aaa5f754	\\x00800003b6f03cb63c5b6a0af1ca949d2050d28e218abe3b404425e1ce52fa13d426a6fb297f5abda58b0055dc051e5f396aab25294632d794460118a19a3dee400c0a72fda4ae7bb8fb9ac7b58d21efcade7d2e101125ca9e4f4d34b80143a0dcc393a96dc0c1477d72e69859b7bad191044fbbc4954c7f36922e3ac801b0c6092bfc41010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x16051056eb7cd88c4675d0929084d66a48820e50d4a4dda10600cce94bcb866b6b6cee73b13d13edbadc2ec220b4cd5eaab11c9faa0da5579bd86e0106840705	1635139712000000	1635744512000000	1698816512000000	1793424512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	382
\\x999f46b9181f03e4492ae0e6f87dc5c9b22d4f14293cda3f33a7f9c39b88577d8e579daeab06e1cc5a3427251237ab483c0980b529722fdd80863c7833f4659c	\\x00800003f8ed2db4b70e8c63fb56bf8f7527b30ef1a2c6cda093924deeb3dc48ed4a6a985f2c680886e094c2a2fde6047349e2d1b3b5cfb15f30e1582b03d65f143239c1cb5d7e95d82fd2832280b77b2d888ddbd2a29ca3481545f6827a67e03b07c5bcfd9b4e987411c8c1ee859204ae059dc1d837cf70eda30ad2569aa92b96f8cfa7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6d0db395babe2a2ee8250daf051364c1317368cade463261df0ba636544ac686a25d719cff7f1869a2a2f261a0803ffffe20286fede57ef2a009f836ab2bc504	1616400212000000	1617005012000000	1680077012000000	1774685012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	383
\\x9c9b084b13be63dafba56eca6c54a795b0fcb1088f5c8cd508768543e12c1079b069d4e2e7351732066d945b256ae1408a8f58a58c51208e972a5ba77b51d2c3	\\x00800003b90266065d40bf115b7d807b3acd20a5c484f061a31d39e90464525c1bf2d9c52beff2ec13b4ec1fcfc4e0885305e0db12a858663b3319f07a43d8b56341d557345bdadc1513de22a0c6cbe7a431f01111427a7abbe42d80bfb254b92c80e2940868eb752cbe4f35be4afbc6294f0f260f933fb5d4c7f78e4bcffe0f411b6b0b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3c282db8248d86f28d6d97f1ee12d7231c582803f2e69812b2d29f7527b231e457388e2d72a49f8204913462f6521fb248198ae31aa4e897c651de7ead1d7d08	1633930712000000	1634535512000000	1697607512000000	1792215512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	384
\\x9c6331d6184d0e7908e87fd84f8f37db3e68574edb4cd06d8c346f737484d24508c42fcf567664ba4b81aa8d7371e88e2b946b600983ad046b69325ae34a2ef7	\\x00800003a3124e957c0ec390123ed2fe347f2bc01141eabe11f32fa7b05af8c0719c3aa4ff58e03fb3e0e2b6776e68d5b4b27c741b0c4b89e13c1462cad22ff120af2154e5c0b2cd1c93a73981b476cd908f0059ef750623e4316eb61652fe57c0ff8bd6dcc6d5e4530a500f5cca72c4ad99cf6d1a40ace9e62bf95fac3f66b4d75cb403010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x0637350b31240fe6c165c45fcaab7c8002210e682ddccbf49c061b3cab5637809ed1d4fe0b513f0483d9054dd5527cdf08e0a02490a610401dcd03e533a69804	1639975712000000	1640580512000000	1703652512000000	1798260512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	385
\\x9c9b741fa3de58a8c3974f29859e4a59392dd62b3a32fc2f1242d43904c64ea2e68d573bcafecb13f84ff9fafe54448e470ac624d6e5e6ee360eb34f2d5bee5a	\\x00800003d7b50c20628e37e426c87068ca38003a6085eca0288e81ad5edf7d11e8ab0b4cdcada60436383aea60df6843f6b680a6eda77bf40e3119d893444f35eccd80c3c9185a696054861ac9e9f20461807e66a384d13f4b45b87fc8cd9e5a625bf648f9c7f89effc73c7499379b7d8c16f8a53eda88366d61d188289b40e8825ccd1d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd96ddb36a8fbb7af517e846cee4a61f3b15f7f7d2c7ade656738385b44df1a807450f2915d8676ae9e414c8bdd9ed33aaf6463e87bf8c139e1b2f0e59d1ca300	1631512712000000	1632117512000000	1695189512000000	1789797512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	386
\\x9cfba56ccf118cce6797af4eab6530ef07e6f75ad1f3ef4b5a20602905e276f4b9588ca528891b19e1a0ccc05b26eda43da3478f5e4fc53e9b38288c2ccbb172	\\x00800003d0c9a882ca3aa74c33df002dc448e33702332402d5b6b44f923cdb005579428e40631c21d21a1c8c2c29e8931cb40432285e5a181cea38883248f418d157b334a393d3f76635cbf047ff63e38f0aecb95f544a7dec8ff1acb9a0569c2ff3db04d1b28c6b22a87593f5365c139bef98942e7d5cb7f7dd952a93f8423f7a930211010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb95db67dfe1f8a2ea4bae0a9ee227c0d94dbf29b14d2752245693f136debf267f9f9e5a30a49123c384396edbdc055ad47d16972a44a75e84efaeb6d18ccd609	1612773212000000	1613378012000000	1676450012000000	1771058012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	387
\\x9e9bf6cf5100a67276a7faf10fba5f5dc49848234f6a2713316ebb3495330fac262ae2eaa7f7af21a0d6db6e69e7917b544412b798c2ae5e0a8e19f8cecf3cea	\\x00800003c8c0048d413fc864a9a64af0384d9251010f1d051337c1b7928255413c7e5f83d8c9700dcbd32987b93e37125af16f0c3a3a0ddb075eaaa42dd6a9804f5c7ce6c34820fc92eebfa45ccf57470e4b34c46452ca340ee2f0d86096863fcaf2a595e713d6d9dfcbb3b9ec070d1781197c62a8ba3a0aee0de76982f34840f2beef7b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7fac3e9c8f9f798c8ba689bcd5782df8d80127963cc3da717a233ca5fd67d3ae8c4b20e5bf96074909b953bd98445329072889da1ed89f8429a219b531013901	1613982212000000	1614587012000000	1677659012000000	1772267012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	388
\\xa2f7a95ff33076d306d52a9252781c3f8114c9dc87a82ca9febc5676b5d7a4aa3f0b740306b08e39c86d9a2766d040f4d92133745525bae4f8d5b3e9060827df	\\x00800003d0a5628a4722c627b1ab1573e2a65546c05d7bb5f4e213bed53c9a6f2e90d70010fe8f5da898b4bdca6cda6d045f9a991226ef52ad3daac3a77b67770a5136876235091f19a5a76e1e903e94952631b1604ade25d87e61e1f70f6b32f010e3462d7ebc5cf55b7ad0ee4eaf2d9170039f51f298df991e1aeced430292fd29a99b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2b2bd41929cf5806449cc4a46f5d2447762d014b0abae1e5185854859bc3cd68d1e73ba3ccb6cf5dd7f2fff1ab19ebca37069fce16d91a0aaffef0692f342e0b	1632117212000000	1632722012000000	1695794012000000	1790402012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	389
\\xa56fb6320d6ceb841edf5c32ad474d509d098c79d3dc61a66b08fba3935a1eb6fe8a46a9b473c133ef2a24737baa412b1d398c8a9bca7ed51c914e29b00cde45	\\x00800003ad6c5bc1a1087279001c42b9691e045c320e127d18809409a79253013e7b0479d63ae06924715c754acf71010fb0165790eb0a806406f137036c1f4830b5d2480e1aaff7659e643eaf38c664c14d00d464e5fe81d5082c6210d585277df0a887e050a3d133e5b6e192f79407dae3a83b79769e8af74434baf8ee22b81c29ecc7010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x633b29a67afe5f53048123df80dbc19d43a4cfc17ee6f298578d1ccacc37a0bde8aab1913ddc6c2453768ec3b681a54f3219ddfd76a3af638808e29f18c03806	1612773212000000	1613378012000000	1676450012000000	1771058012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	390
\\xa7a356676f21ec9464d144af55c2b5fe5d070ca9e90e0ed340f388cf4dcb5f45891527864e139833d5e6f39c87f5f9af3bea5a93a0df46fd4571ad2dc9a9423c	\\x00800003970c16b87e882851ccdfe4c295fcb167e63e886531a061ed548b2cbb54a0c507adefca8e2440805177a07cb82aa411345203fcaa82408dfb0ffd20bc48992f77920e7f4555acdb709914eee464b0df86aaf968d9162d6d818f1eab3e393aa5cbad6be3dfc83faf9713a358b655275f331348969e3dbab5698790bdf580a7c52d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe7a6c0ce4577514a42254c6ca7eb1a0bf87378cd0a61dd66f5b4e7d55a1cada3905f6edb982be5f03b4b36509d832aaf416623c5b287fa12c58c2f8309ed5703	1638766712000000	1639371512000000	1702443512000000	1797051512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	391
\\xa82b22de5b2f98175ee8242aa0e0308c7148b2c64a433b1de69fb4878f087c3addaa2d5eb080c10444d7005ea86643ad68735b79fe1e978c6b656dbd6fb378a0	\\x00800003e0a05235d3a3dcd3986fd04c733b2fabdab7c5f31f884107e9e49694a64ac484c4da71d6e2a84d546b135bf8bc284f8eef380d4c495c42f29a1ad8567f5e3419ee618bfde3d5cf31c885436e137e69efd8829069fbb34275304ee5c561c976708eee8537bf9e786befb0c1f4e7a6b32a9ddd5b14917efe5b0847b77b31d375ff010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x825b80e2ebae93c633ab331d9fb5822c40ab89013aa7fb4e51e9f9c6bc8bd313e4b0f1e8f7e2ad9b40c6d18cda2429956b2ee5222eac96f1893a75fd74b8ec09	1640580212000000	1641185012000000	1704257012000000	1798865012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	392
\\xaa8f7990fe864848fafab7cac9153fc3ff34b011fe61a79fbc88483fd9795e95df4e780dabc21270f81edf42a2e995ae980954cccb66a46c78e39d4de93c82f0	\\x00800003b3d505c9fe1773d70c11cdbe70af81a86291d7c962a329cc51d8ab6ca3308c905e7a5958b31b2186722b2eba94230b2f861a27832c84c8b72cd93855a7aef8b919cfec822bfc5806851d7ca4c28206304c404d0b1c36c8c35fdfc9360084548cb4df853a5d8714863bc859e43096ff8c9d94a9ab0e9fc003712568cc6aedec1b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb6f9f7543b60316cd7bdf10126c72c8e22796e43688570089ac4adfff4ad18f82d25d0d4127b01ba6cf1761af4367efc1a6f187d5c333caa1310e807ab7afd05	1639975712000000	1640580512000000	1703652512000000	1798260512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	393
\\xacab7195e19302e06cba99a524d637f9ac91b77cb1d20362167f579bb72c419cb8e4bd44bf1f282f106af409e151b659c40951eef91abf86c7b37a8a15ca85b1	\\x00800003dabf9c09350eb3755bd4934a99dd3613a43ae766546d61b6a604a51dd4948f14ed638fa2139f9a9386a6f16cc9ba4b5ddbcf6c907e1ef0cfe98d8faff700b6f880b132281de333d4d10c4624789d4e4e386095c6d9727201997105fa56e7b754b1a163acc587875a75e1eeb115f55ca5c36885dcf40aaafa41c2c8b576a2943b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xca6d0963bf7c94b1216ad820278ee740495a1e227693a96c715b71ce645256d8ef75e45560974eef2e70d8754121fb0a884aac71b458a7230700d0dbbdeb930c	1638766712000000	1639371512000000	1702443512000000	1797051512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	394
\\xb00bcb1fe1200310e62bc154ae28ace4410995828b4089140767085aebb15de45e9b88cd053385c29d8bbf1b46297ac5f7f12b60d4ecc89f9907f4f7307f338d	\\x00800003af9478aa47d09c8e29fbe4699924b39bd92d600c165a8b2234d13b4f5cbeb031a4c9108a3c2cd54f16e12fca8263b697eb856e12b48b27c6fc5d8de61d8ff5cf73f19b7133fc6aa98848a79e6c4a53207a437408eae510bbe7b8172476ca193d056370c1dbf0bc253484dfd1fd936e57698a2231296853c94c3a2674c7501ed1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x34fd990f894f619d234cd28274825778a9636c2e5bc0015aea2b9b020f23652be08d3caa650ce4a203213c1c33ab4b990d55ca494150cfc86dd9a090e2fcb10c	1615795712000000	1616400512000000	1679472512000000	1774080512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	395
\\xb6f3e452fe632f5821003157230a3fced14c63bd72377d764affe3d1c31d343f3d221bcce824d0d75f51ca7e9ca3c8db712e540508c7fe6440fd61a21e8a76b3	\\x00800003e8147a6f043330233fbcab38b5d9f55764d12fd8aac0bd0c08df3e626f570bcdd7ca9d94fd63fdec0e6867a1e17973be4b93b24be4ea29eb5fab13d64addda31314200d8bc022eb278f1cc59b50d9eb7e1a1df8af8d5aec1fd2886c565e9fc364c78c9059daf2dd8870155ec6b1522e70c48b271f586fa284afa195639e9f8f3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x9d52b41b2043fb8d17651c27eb0666e329d0db97a9c7e7ad696f65bdd15fcba66b4ac21e649d55c61ff8282facb8f29cd9f80bc21b034e5e76a43b8b20520601	1614586712000000	1615191512000000	1678263512000000	1772871512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	396
\\xbb370fbcb0607b168ec10fa23b3a0578e703cbd161161d910973c367df9e16126971c7eb71766e898e2705490ee218e37a29f7a2e04f28d14d63f6890877ee35	\\x008000039db0fe8977e9d7dfb7d1c796f0ca4e894e636d53957e6293b33bd8ffea0864bafa1d9e1da68afb4a2d58e73d643ebe77829866914de1b132103988ab8599d15170f515ef0f2cb17172bd18e1ed1b589a1de72d58cace59799848666d71c7a5c4d3a4993837e32c64fd709b01decc9073654382b7e1312c674b67b6107b96b0b3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xab5ba84de48a2fab846f6eca8642b28c2ce66a2ea22cfab63f8de07a8d7b851a522ef587a93d215513e1758c302c6b3ef4dc9ba09799283256b7b56ecaa92504	1619422712000000	1620027512000000	1683099512000000	1777707512000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xbd4388bcd28ea4ef24a8abb37c2fb01351af3bd2bcf99e26943db483da8ec13149c2046909c72d69609fe80760974f25237de22b4be3e9e463a62c54d2cd3798	\\x00800003b0677fb54e05417c72d0e805ddee64f3bf8f98fc2ea2db4d6db360e3f20a547be385a005cf83784ca2c20d1841c8e0ff990bc140a7794e6daf029cccff1b2e17ded8a9b5462016d99bef0452b6cf5c715426c4dec43455ec692782410bb6723082a292f9900173610f1fd0343890db75d65285e85e7dbdafd8c02c4ce55b2e3b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcb23d4fb9f2405532fd5cf8b710391d1caaef03149760476f0b0c5a1cf912ffcb8e7a0c68d6d87e45d4ba2d5febe305574621ab6dbffe2ba8a75e24feab55d03	1622445212000000	1623050012000000	1686122012000000	1780730012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	398
\\xbf2b55c313d89697ca1365fd6a0a531bc45caed534e74a20dd65505ba0f8f3f928d8a3e0664800e1858a7d142acbd8b4092773145d446f445b9389c15067550d	\\x00800003d885fb6c5dbf811461ad4ef5b991e6218068d952235a46fc80d80a1d12dfa2a308c742ed766ea567a8a3e53b42ba4efe8a6e19afa582e0d328ff8cdc27c53708eebf69a8b75ba800047f0cf52c317a61408acd8c6069034f35592ad64f2f3069c31b18df63119b2e110a97414fcfb1b7b80dee01148a691a4c421fb18b3a5eb9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xcb4fabbc759ceeaecd8389c1db3344e9fcb10e7d0b86179730f1aa7949bf24af7a56e22d65c34ee8026d3a01bfce60e94bf716ff811cde26905c6e926877f80f	1632721712000000	1633326512000000	1696398512000000	1791006512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	399
\\xc18b40d7e8223c24b02c547a506c52d954f0afad2e061383c90e99f4894c092f5fa4b0ea7666b366b9a858fe6bfeb853df6bb9825e8e2404c7a96d5a4390f3aa	\\x00800003e14f8be5b29137cf82a77dd2ddeb402610662411a2d9cbd4f81b98b2ab88a13c903cd3a3dfe6c6d328f782f048a9189023683cbb9f8e508ca8c72ff862a07f6bfbe5e59134a4317a1c8e6b4ce62522efd4d1491156d6a1a17aad07a409ce5e88632ec56a1c0773d1edd9f9ea7deadca6b8301b78fadde8bd6a4c9e227fa5cdf5010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x13065fd2fb77017d240e66ae5529169106ccff388901278dc628afe1c350fda55c51373c4540b1939da33096a6cc3eddad3fdef65d3659fbcfd15d74d68bbf0e	1641184712000000	1641789512000000	1704861512000000	1799469512000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	400
\\xc19762fcb35eb6a7c97a1f4ba0554cc1982ef1509684a9e98f7c2913375e3ee4e1ecdde827454bf7ac91f4b0fc5de3784790a63bc7411c3088d75d882eb74094	\\x00800003c035b97fe593802705f9ddedaed9ed3e49570c3376b9a48347b694b4ed200c05fe4f47388a354e918faa2f954bdc06a8312ca4dc67d1af9fdf8e07ea5c7e537866ac91793710575c2ebf13123a0b1229175f4c9652bf6b253f9b8f9962ee47b7f15a47d5081da62dbd8651075b6d849762045bd8cb08caefb589c3e2dee55ceb010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x613425b54e6369e610b31518b90a97e8ca7c551e1457029d4e4897be64b12e1df76dd70c17ae9f80e5df27821d0c1ffca9375c1b1a395dc4175a767e49555a06	1638162212000000	1638767012000000	1701839012000000	1796447012000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	401
\\xc5f7fccd8f240876e51460806e5723e4904c7a6a64568250d0e69b890766cdb0911aa04061d5f8ba0f931f6eb849d24ee2d24b9c0fb1d97a0982e8d107d7c6a6	\\x00800003cde5ff407188e3800e7f1fe9dffce46cf694be45785db865bbf543ecd2fd76d9e4729ee546d668679cb87f55baf3a70a25e6f91d2eb438b4221251394bf9f34c9e0fc4267718af49cc90878437bed6090c69d112eb8eed8adff55f9331588125c2005a6d2f2ded42e8e7394c9f75df367c99e88912eb94154ec12b9378651a55010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x8e8c1e6e9925abd617999362c7429d0cfed87b39d6c0138f3385d2021385ebe2b6d333eb4bc420e05eb64a4f5333563cbcfc1addb5f9fa2a4a6c5a64f7a4b60b	1628490212000000	1629095012000000	1692167012000000	1786775012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	402
\\xc593a37a8a42c459e96be923ce1c6227419872e376bcb1ff109b77d95a6dadeafe8b7a633108c10f37fdf7af4452bdc53c68d09cbff8ce7f970448cde1dd37bd	\\x00800003b464672335f845234b7aed6d68979230a5cc3e66f641144fbec60e30ff4d21b7d6ee95cdcf8749d8e2a1e6467801f5f880f679b78fd4c26d10a4959df8bc6fbbd8eff8332d36858499f9305f02ead2792b2363bbcd034f8aae069eb5d4faf35a476147b230ed3d942a44f39c266d5a5a323fb695aacc1cf010a27cb96d110387010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5a0a94d3743838be312fb040279c723bbe44db4e5e822127c03f3e1b1a9a396bc13c60fa561b95b0c080da2d192602c3fad0ee7800a2ecbcc9e6432b066d4f09	1632117212000000	1632722012000000	1695794012000000	1790402012000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xc88385263fe5468532b517fba8fd123cade6a962e7d4ef4339f11052774d8491cb523a8c295e46f84e352443b252c122cb197bad2a0d58e4949dd08c23e3d977	\\x00800003c873358fc6d55691a5b798aebe705a7b382fe0ba782ab9b2f3a7636b33ce097293522fed3a7c12b376cc513df95f29e3a1ef6c0a02f07f7d98d79cd21c20d358b53131e30902639deaacd8c1269adb9f5d19335f7301d97031e4fa93c53262c457d8bd1304faf8faac9b8594d22ab140459176426c0223ad741aac3eded5b123010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7c45c2cb639b6fdd9b46136c0eecdd2586b6f1592b536706c100273f45691cef789d2850387edc1a582938982d5ec150f022951615cee07998f4659591f04c0a	1636348712000000	1636953512000000	1700025512000000	1794633512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	404
\\xcaff84beaf3c45dc02fe0ab54e0b59c546be238696841e630b4f2460702b89df7824249274346e35ebf6c5bcfd4ba81b737243822f1c1fd3d752fb0d5db45419	\\x00800003e4a543e936ce8e3a5de730ebaf8d04faf2a75341ac17dccb41aef1a98ab7f22913f85472db4779c4f09322344280c5fa974333983aea53decf6eb49892fed532be3289e8101455dcfca1953b87f1243b6e6001dda564bd68957eed55da4ac292e8d025e843f5e3bd9da2273031ad57313323a3b0ff0e5bbaab26b771dbedf31f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa2b3a720a9d6457e6d4ec33d21352f607a7c866ef85cf63020db3db7b85da0f92a530433d51231d2859fdda523d952d8ef183c4cc47600d4f643d99105cdd303	1624258712000000	1624863512000000	1687935512000000	1782543512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	405
\\xcbcf0890c5b170a2ea70ae4ea863db8ebbd0e1d4a58215bf31de52c52b5462904030c4b7eab78893d5c23e9da3dfdbda96e6f18d14fe0a92953f8d02b6403036	\\x00800003b34c0c16150b45b40bce0f90bb233a611f5a10eadb89e90c0b453af0357c349376b119a0e1de8cb232de6d664a8ced661f1bf001662936757bfe4fef22a2bd40d4bd7756d4eb0c35c4be40f3ea67a2db454fa7c846534eb2e78bdc9d10a0a6b19a46fa3a74c16d7d94be5ca04bc78c36a072c90eb511c9ae8e06f27546f14b6b010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6be8af53f68f7cffecf5948c846db3269137a47c6e779b9b6e518c45a742416ef9fa922c414ebf78db116876e80fc07e649ee9b60ce9909fb5ce86cdd483fa0f	1627885712000000	1628490512000000	1691562512000000	1786170512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	406
\\xcdcfb84067c45921c4c29a67733eb5527aeaef3aca90215d15528aa8ba286c21f3abf51e3c1319288901912cb6537b14015dd1a4f01b2d871447e29dc076dc8f	\\x00800003bcf0235d32d58b491a9716d059a64a586b6dfc1cd8e4d70444f32c234fe40c5006d7c4cee99dad1d815b87c8dcd03b3b716018aaaacfc450744ed4a47a5eab575fab02c2d1d92dff8694ed685d46b730f35de901044a0647a0c621f8c90b8dfd4209f40f4d20dc265059acc64df3e8d54216653d216b378b016c20e621c085c3010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xe2f42a404dcd93d72c1b3855f87bd30e0c5ad230a7b441ef11122d11f15f14a3d42608c117b22f4e699ffa4ce79b5ed17e90cc3f41e8e9b529577377a98f6c0a	1611564212000000	1612169012000000	1675241012000000	1769849012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	407
\\xd06ba6acf70e6d5e3ce00f89d77563b1fe5c81235435327487ead7a56fd44a5b1572b10f8508b4e69ac9dc273de4edf69c5b5ce7b7714d8c5ba139b1f3fc08fd	\\x00800003dd9b89a9cafb30d12da8849d17a01690bbef50a5247b85e9d9c5e43f460ae6444c128bc0ecd0ed547fed5315e1f916b2f4c3f022bcfc4104c9a6136bb9a0e845a75c0a233adc2e9e2df670e30071dd1854fedd9941948151345905b35ba4ec3d45efd398fb44b8e83f0c46b67bb9c4d8497c741c5c4d1133460621ea29a963ff010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2e8ea80a2f932f30a2d657c1809cbc29a382deef09be3a54ed4ce84e978cae9089da233e9f981e0c97ed655c1b01edc1a52a58a0cd694293a592d0f2259eed01	1639975712000000	1640580512000000	1703652512000000	1798260512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	408
\\xd323c6e5681a3b0ccef6d0383cc637723d21800d136464e721c5bf96316238f30eba6777959566a76f27096a33289a20c003f27e6ab0d69b70a8efa1cd997e0e	\\x00800003a98f468a2fb7658bdbde4f517f7dfdac617001476668c6cead861c01a2b38e1498aa2510b1442d38e85d12711264394b10417b2926a163601a9215e9afe14d14d60ff8d28664d56d07d1c2449a0b03be5fc28fe675e682cd46bb8258b5a350e4e6241feb1e12f14dd935986c7491780673ef9353d22eb31e97c0e4f276dfd325010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x6ce0debf1d98a92e1272ba8ef0eaf96ecd1bf76f6730b5252cc462ce4086a942590fc6189a48c455a3cce1fc4d0497e7075d0e85eab35a9fad8916546f57ef09	1635744212000000	1636349012000000	1699421012000000	1794029012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	409
\\xd33b01387b8d33b5dd4294d8afec188ee709b2002e5e2761123f8903ade035f7f4d36aa06bd777bc203c0153fd07099850b358b1c8bbee1b361219820fb67a91	\\x00800003bc43f82c710e8913227cfc233faf0b18b5b84c3e905ca5e11d6824a74eeaa6e2a67945cbd237056c58c518203362c09d4123c2d0ee40ee79401b60416fa99de2efea2a046f9c7a30c5f62b7e1e7a7862b2fd8c971f8540d2470099ad34f69a9d4d4c56a9cacb9e3564907f48830d587123472fe59483a9891ff0e335b45b790f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x3c542dc384539b115687931d7ad764ecf88f56a66792e9ddc72352e5befd484dfe160f73134a35913f20576bf338f05952e709a5853174eab585bb86b4c3de01	1629699212000000	1630304012000000	1693376012000000	1787984012000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	410
\\xd567f1a06c9582886a99b755de029dbaf7077fefb0a774ced5c5281be9663f9e9d5f90572ddf360a1acc8c72ef5fc75fb8a8835e7e5b1841fc6175c1f336e00a	\\x00800003ba06c40681d345b3f3f925b9c9f757643f2aa52594b94e83b16e7a23336a6672dabb486935b65ae7fff3d8dfedaa839f5681b9e484761863c4308bb2131aee6bce81695613c82bcae65439ebccb1e4722885c15e776b9d9ec147d18ad736b361e627d388ab02674c9f7307e1ec0399150fd5e0cf8b0fa844e8a4cf04ded4b35d010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xa83c2de82ac0b7e570098e508baf04094db448f65dd962963ea32f3d2a7cbf499abee8fc3b55293189f3cca4e81f5448a2abe2948b55b5ce4df1e39ace396e0a	1641789212000000	1642394012000000	1705466012000000	1800074012000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	411
\\xd6931eda64b0792f94312eae80cfd98cb2b587b41a86fde09810410613043731620cb343bd7f3f15d7d9626f27049d1e2742188f68f473e98a748262e4ffb183	\\x00800003c94cebc2224b8f2a422a74aa2578ad1eea269aa836e39b369661de3b90ffaf975b992f5a5b48b6cafda235e3c8f871c52b5cb6f41b53695c6f447debdf8cd25234c10fd5c7cb22ac6d693ddcf4259265dc0238382d82867530b20e614a94fab4fb18484c8e8793b08bec6ab9156947adc2d36830330c458406acb2d8d02f0bfd010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x91a38ccc2be62be6d88e5a091114d08b4c1c562c967994b281f1046ab1126fb69ee32ee1512a4e8ae12f68f86f042dddb423f67cf56e3dff48b8f446e02de00e	1618213712000000	1618818512000000	1681890512000000	1776498512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	412
\\xd7977c7087044badf7f01223024b393d2bb1b9b569f944bcdfdf99655c994a216e9ff7948d69285f7a00725bc1613b68eb5bf8b82a74a4f26b571116ba3c702e	\\x00800003dede87da28b58eaffa86357a644ca668d977c0a3afbd08fbafa6ff08381b2a9bfad9b29ef6cc57619c3522e749dfbfe6ae9432e9d9c0be15aca152761ec5fb93049d0e6527ffd15f5658f7157be02baaf9530030f5a5a071bdfd50be0a7130f64a4c41de6f6395496ea3ba2059ead3de1fd85bf502f73b3e500e072e57734a41010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xc7a85602da9575915e1753eaf611adceb844ace32026f7fce5d02c900035a0c560abada5f39db0ce045a7b4a05bebcae3e57da5f7d8e60525d31bbd96b386901	1621840712000000	1622445512000000	1685517512000000	1780125512000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	413
\\xd993a6aad1b0b9eafdaa3f6c28aea2cf2cc70b6dd2b88018bf07519efc65ddc0b53d8b01c6dc77e001e808d571dab5282b8d595821f1fb21d9a9362e37df9e2c	\\x008000039c4045aac8d9ac0cf946f888336dd29d20fa1759a0ae323ec3c025c32857acd36154d3f38b3c0ab08fe6effc814096d0d00b4b64138c5bd4705930e44a7449df4e35fd07584bb06c09da71808399036143bafe69dfa60444c17af215d3c41a98c3c4297ac13dcc4b42fea7c114a20e603aaf1ee1c76cfa3b297cb7ef5de22bf1010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x11206f9338f9443fd9b9edfe44a14c6960046d310f12df4de491e915b8dd77ce8c6221bd8ac5a287ff8309a68338745fb74ebfbd28fdf668c8c34710fb5e610c	1630303712000000	1630908512000000	1693980512000000	1788588512000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	414
\\xdbb340805d008fb1ec50d7270d6a17f049f32229b7e576bda24d1f1872ea8b55d95d20fb896bab3d3660fb2df02928f6a8fd402ea60041585289ed1ffa459eeb	\\x00800003c3661ca9dba4aabe6149a6287682945102101d2bd76e011a37f8bfd3425f8b53e8f2057cc532be2de23efb9f06bac785c559f0c2098b435418bce7e7a2a7caf3e5fa09a58cc970ea6e4000cf3eca6c5a6c43cc121657fc66d22068bfa995733a98d92165da0bb832a16f29b50f0645f98580ce2822ff7a84b04dfa1c39e549a9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xbafcd800b23e765604c2f25ae7f4223186211b60ca37cc4356589789058f956816d7c30fc87a5e9ca71e63c32302b22a7cce9a4b845a9e673cdfd641d774b003	1618213712000000	1618818512000000	1681890512000000	1776498512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	415
\\xdc7f7bee8b43fc93878ac772a28e3e33421713f1c10c766e42b0cb40f98a918f10d0950df261695457060ad61a2e874aabd8f2890fe28737f841780853e412e7	\\x00800003b520c2bbde9d7f6e26f5b979b0edd7aa91b0457874888f67aab3f13c21765fdfd769749e3f6e40fb7b4116316b29079fd5aa485678a16e1e1d390c3ba158ff7891517ffc3a6839c39880834aaf1ed43e2d216041b7f3d3b0f5f060b0e54661ce5dabc12fcf906a71981fd43b3cad7fba8fb3e1acb6e54a2ef1349926d9b4e1ff010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x730041e843c875d31231b21876d4d278b928de14856788798b321076ac9a2e439666f889ce622400526abd44c7835096d167c64ff569ebc498ea451c42e9f009	1623654212000000	1624259012000000	1687331012000000	1781939012000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	416
\\xdd97865b70eb9128ce1289443f5744d623b73f9541700c9437e30da0eae6eee4edb953c72b1ab77c1f7ef024d7983f1fae4cb4fe01fc05558839bc6820399a40	\\x00800003afbb78bfaa3f7d795ba3257546f5cf99c6a3abf077fa2bda4a5fecb834e8d3397986d1f2fded86b197624eef6d918c8cbb7f3574e6054b88c01834aa2bbbeedc061f6425b46cfdb491553ac394a58684522b56af09101eec106394de212755dd93f78ae0350a2d79cb8e5fa054db0d6c92197350c23f52b866c3aaf91919a515010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x1a1b44efee16556409ee8636e528a273af196926ecf2947235f972655676b08a328a1b512e68cab302797509fb08d9e9c78ab1046dc4c691f053b39c78fa970a	1632721712000000	1633326512000000	1696398512000000	1791006512000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	417
\\xe15b0349f8f53c3a9283dff3b663cbd5f2e4a7775b7566a49f9f0bccd7e827c37abebb867a25dc42c83170ff6dfdebb18868f92e7d5ace4f39d834225b2fa533	\\x00800003e7c6654ade3048d55d4893964ddbd1818c55d1f849624fe82c3481adc83097ccec530cf699cdee4391a3f98ab8f2ff5c541b274779ed6fd5578340153d64b9b2daa5f61819962c47fe8915ac2970822a7364fa14d82a4a92b33ecc82b4625e60a5e1ccb8af515bd7b88b036a4ddea6177fcbd2f0ddb7503b39b3b61d1c297091010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xfd9f2233c6ae6cb3a90a6f424da09a766e67cb1f863c24f43f5b67676cd508395142f20cf3b0a0ecc6babe7a770a6a5dd20a31b9294a4541691ea31e2ee28007	1611564212000000	1612169012000000	1675241012000000	1769849012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	418
\\xe90756483069d86c2225275e72c141714a3bf328462c14998f644247ba973c62b20fc450e4909d28f7a12d65963089478d15757b3242a641d17aeb17e3f7acc1	\\x00800003b17d0e926aabd7d202a993525a3542936ccca6123e3b42fa254d83416ba64bbf024e8803894f15a372ec66ccde5c54f3ef8d1eb09dcc87ebac48624cb0891294a1c02bc096a95cc96133d40a8bec4da776eee73f018610a4fab298dd69c55305e2bbec02fc2994ea8f5378908a9e651ab0f4c215cd8e5b65ebed833ed6cab933010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5c41b7be2757abb1bfe470760d413197dad18b71a3b7469b689e77653df8e0b4e29a4bdd2ac02a18af28165a98ae6539206fdc838e308e359969606054466e04	1629699212000000	1630304012000000	1693376012000000	1787984012000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	419
\\xeedf294a22bcb7cbdd98434585ccc2c04408e5a61086f016108b6f5279e7b0580dbd609373252bad9e2541fba72d0e014c11d382ffec548f5bb78f9944fab54a	\\x00800003e160b1c62cf98cfa8c6b2281c110eb222599b3885273053be13156201720ca3e0b157821d114c52913fccd99693db4b0bc70d134c63fc51fc1c7663cc1b34a50a840891239397cecdc28be5b633dc9e03eb5b483b5ff3eacb180bc06d2432814b70ea2068ea3fead35b4af4b1baa1e3c2517b27e0e484612c9882620e732a013010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x5251cd005d52165fa58ad449d1a3b46882be22c4450d94b49ffe73d3e30d65f2013b7683f9f9d2cf2d48aed646bd91d6871d72bdcd549b001361e8846d642809	1621236212000000	1621841012000000	1684913012000000	1779521012000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	420
\\xef374802235623f2af5b8f2c360613369e251393db52b3872654cd2c871c94dbd623e8f16e7400b515f49a4212e4a72aeab7757ed6d621e6a967ef8997debe74	\\x00800003b766bee1d319d5be86df47634a12453be64130c45f9e287a523ee834ec578a0b3cf718a98f859e0f99433a1ef09ef522e9e4a23a36f5d5e2ecbe10b79bd04c21b3cb32cc19ea5cc3e5a02781f43b840deb3a3261851d23f0dc05f5bfeea674297fc98f312af5a5330572c8e696b57247271d9d375fd1b8d7d59ce823069ddb25010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x0ace1dd104fed31b18a897b4dfc7d18945707743d5fdc917e1a0318dd1d1297d137a218e8127366b040f8d492135bacbe91de42c46fe3b11dfd85d41e9284904	1612168712000000	1612773512000000	1675845512000000	1770453512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	421
\\xf343997b537fc3d5cb70a836404dff39469d3ff2299257831443b145b19b54bd7a0dad59cd7db89a115f7ff0e84445980d68ffe0166b91f82792a8ab71835bf5	\\x00800003e35823a6224a2a9664601be2d10fa134e0b053ea6ad02283119c93f5c4f38f96190bbf1ff985ee7b3ca84638dd82276feb63630c7788197f950f086330a03466da4508d76e10a98a22fb77e4e19533f65cee7451adc7ca4082ff7d0cca64589d31678023aaefe164b3086c940beea105cf2f253375e6df230fcca00908df4c7f010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xd307f99cb137df017a04ba6ddab948ad36898ece11dfb663dfcf57f95f846f34b132caa1b059f637a7c2f70515c50c48edc005ed8310be2b75aa8904ee91a40c	1635139712000000	1635744512000000	1698816512000000	1793424512000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	422
\\xfd4b0bdb3f455973c558a96896b4936ca9f19219a180c7c05b4898828e8b952d99654f0783e9de1ad817050d6ad65efc63fe785f3ad94cce59ea17ca404ff2e5	\\x00800003ba61ef77c8935a03da3762ba0e701f6a0df0a2a1fb3fb3ca0a35218629b347555508962c2f20af5c3668744c1752bb3665cd6f56bef9c310dbcbf1b31145024b2654f3e99fce2ba774f65b40ca3cc2297cdc428bcac421f51e8a59bc054874b9126f7424aa246eb0182d3249aa91d5c59bb1fc07669a142724d51284bf7771f9010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x089acd4f1368b66147a5f0a1ef90a9490ec2ecd555f79db5455a7325b04b2fb2c11e269cc4915e149733f09cdadaa7ed84b651940b4166226f1c478a1f7e4704	1641184712000000	1641789512000000	1704861512000000	1799469512000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xfdab0b9ad87d29a3b38d74710b740e1f54f00b1e8108d69de862a4bf21d8e79b605ffe6711331e3c5ae59d2e8e701c6c047a0eae945be213c0b57a8698ecca95	\\x00800003b240ea816c0b093528018824364cb615da006d59281e079edf32335bb674c52c9c6513565b111c512bdd407d441559875f3d30a1996a719a237bac545921f5aea023c780390feee87fb0da0418c85d967a7d978c2254dfc9aca5764898ed51837af123d16b652cec3ee33b0f5b676c26fbebf40fa529b9d8d82fc7712b361205010001	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x96cc6d65f1d67356ffdf57f1b985e94ffc3a4380143b82e5c0527aecd2854eeccbe78a7bb44417d7009bd7b595e12fc2641dbaa1678e0a34983d4b8f38e50200	1624258712000000	1624863512000000	1687935512000000	1782543512000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	1	\\x437becca6923b054068edafc1d492e4559beabe044150d618e98ada2d5625b7a411703f0b0080f776f630cd97f10cca868ff0f605f92a0ea656437eba3c4b6c7	\\x6bc2923573f8eca180ad0902041c511b1d9caf2fda212ea7b415e91cf9d6355dde67c85b9357e5155814bc06f8ba53ad16c6ac9ec9ad3ddc013dd7654d0a554c	1610355248000000	1610356147000000	0	98000000	\\x89e0876001a110a323e47a140c51c9d11159c4f07c141a7fc00cb361b60a6f93	\\xad01369734f961973a40a5ea0f73272424d5a6bb513accb13e4910cf39a10942	\\xfc9b83e30374c7a220de87eaa722adfadfdd3fd86242019dcb3368343403ae88e32a79524e476e61281cb6503af8a3cf908e3b0bfb833c3f63c7068c72910e07	\\xdd1496eb43a2f402d47bbab3ac5b77577b8811296e71bf982922f1b2df6cc590	\\x29ae0f1c01000000607effc4dd7f0000076f8dfae1550000f90d00a4dd7f00007a0d00a4dd7f0000600d00a4dd7f0000640d00a4dd7f0000600b00a4dd7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done, known_coin_id) FROM stdin;
1	1	0	1610355247000000	1610355248000000	1610356147000000	1610356147000000	\\xad01369734f961973a40a5ea0f73272424d5a6bb513accb13e4910cf39a10942	\\x437becca6923b054068edafc1d492e4559beabe044150d618e98ada2d5625b7a411703f0b0080f776f630cd97f10cca868ff0f605f92a0ea656437eba3c4b6c7	\\x6bc2923573f8eca180ad0902041c511b1d9caf2fda212ea7b415e91cf9d6355dde67c85b9357e5155814bc06f8ba53ad16c6ac9ec9ad3ddc013dd7654d0a554c	\\xc1484690896bbe107626f5ad5bf1c9dc90a577700946f0fe5ac2d74d1a5bbce3775bb84f8b589addc79f6b1525eebf746d3b0167709aded74f84f8e83dbace04	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"VMSVGZDKZJ0CZH8HT95CJ5T0QDAZWA15P8TAYP61C6ENSRRBK9707PXC3GH21KH76P7NXTHCME4SKATF0V49BGQNH23QS35QCA2GPG0"}	f	f	2
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
1	contenttypes	0001_initial	2021-01-11 09:53:32.642168+01
2	auth	0001_initial	2021-01-11 09:53:32.682362+01
3	app	0001_initial	2021-01-11 09:53:32.726575+01
4	contenttypes	0002_remove_content_type_name	2021-01-11 09:53:32.750791+01
5	auth	0002_alter_permission_name_max_length	2021-01-11 09:53:32.758346+01
6	auth	0003_alter_user_email_max_length	2021-01-11 09:53:32.763839+01
7	auth	0004_alter_user_username_opts	2021-01-11 09:53:32.76985+01
8	auth	0005_alter_user_last_login_null	2021-01-11 09:53:32.775501+01
9	auth	0006_require_contenttypes_0002	2021-01-11 09:53:32.777049+01
10	auth	0007_alter_validators_add_error_messages	2021-01-11 09:53:32.782625+01
11	auth	0008_alter_user_username_max_length	2021-01-11 09:53:32.797448+01
12	auth	0009_alter_user_last_name_max_length	2021-01-11 09:53:32.804975+01
13	auth	0010_alter_group_name_max_length	2021-01-11 09:53:32.818197+01
14	auth	0011_update_proxy_permissions	2021-01-11 09:53:32.826951+01
15	auth	0012_alter_user_first_name_max_length	2021-01-11 09:53:32.833435+01
16	sessions	0001_initial	2021-01-11 09:53:32.837951+01
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
1	\\x89128ab141ec2769233f0e0ce4a107dec6123829c2a6dbcad53f5cfb93cf50b7	\\x747f70629d11cd03630d582cb46a25ad29c6bd1ffb3d9af3f291caa816288754463e4a8ca7a31473410e114dfba45080ed5819521572fd85a8f1107205ce2c06	1624869812000000	1632127412000000	1634546612000000
2	\\x2f1ad66d443b984c2429bc2d0a681b518e8bb8446f615be13fbb4ba123d8851d	\\x3d699dce76dd6aa4b3a2385194fba10a6e8e1cfda59b80ac093ca3964d569cdb8443b017691cd47b5f5ac8fb19edd65cf8cb0ccce45aaa0575adc691f829f50a	1617612512000000	1624870112000000	1627289312000000
3	\\xb6ef81925e17ca49a98b5e6ccc4aa14ace3e903ebcee9037d15e851b2dbdea4c	\\x16745d331f17445cce2aeeaec6850b8a804731f802a2b3f75ff1e4b439b9eeb0193916139def6cf4869621f33252a82345e3dedfbaa90ddff79f8d5a2c0d3305	1639384412000000	1646642012000000	1649061212000000
4	\\x7daba82bb80d1a43c4980b73b92c2a1bf0e4b34b9c390dd3b2d8494eee116df8	\\x11962974038bf4e4f3215b168db8f6e4cba990294137b38fe91e35e514b1b455f9cfd15a28e9a6cbaac0ed06e7cab7d637d1c6ba195db4d496709cf2e9093508	1632127112000000	1639384712000000	1641803912000000
5	\\xdd1496eb43a2f402d47bbab3ac5b77577b8811296e71bf982922f1b2df6cc590	\\x49f150d910c50bc03233735effcc4e5fdb0628d48ca685dcc6e01638ce0595616aa878601ca98b4528be37676a5aa3ef7a717806e344002ad0df72064e256703	1610355212000000	1617612812000000	1620032012000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\xa397d79c141bb4392590721b0b966f8cde910a0911656828a8439db5125293a0	\\x59192700a7a19ad37472718eba0da04225119fea8c982d517f66e289e78aae1c748cc154af5ea1bf7f19e7e3024b91187b55d8e2c6e42b53df8094beba0f87f2daf3d957620f30832b26fd79b8a0a95b9e0d2de2957b3aafc46c9322a862b29b96f2e881997426094abc2b516c4b25cad59391e309d7c00a29e6a53f2b9bb246	189
2	\\x89e0876001a110a323e47a140c51c9d11159c4f07c141a7fc00cb361b60a6f93	\\x66a282ece480dadfe0c7416f4eb64c462ed3ce20385a31a40d937893cc752c9c77a554971cd204554860777bb8971423ee4388bfaf10e9c178dbc833a6c5891d85d742ca2dfa280f959cb72e08ad624fb314dabe03f825b06fbb39e2536047295945f6ab144e97fce79f64acdc22e3590a2979bd9bd66ecdb55f52b5e052c068	33
3	\\x949ed7c6c4c872d541339ad8ce64d4ca41b98bcf3d88701727032ba77fa9e6c7	\\xa8d50dab6821a93dba792a7a782ccc4a58e25215c1ac2ba422876083e5805007c79604a079953288a17d5b23e03f5118b35f08cf99671724e26e2c26e6c0563492e0d32699f80f5b3df945b1d695cfa6ef3ea78ff9baa1a5e613fbeb77c1211e974dfb542197e5c2bd53c421042c2b8fdf153fbf1e8a6ccc958f718cd5b9fb60	69
4	\\xe0d33328bc7bd4004fa35f8de1fe6610fd717e0cdc1b722d8a4454267b0ff070	\\x02b8ddc19a7ca603192f374e2a6729ba6109a3155dda12cd7f4fb65b548e164ffa3df4430b3102ef8cf899cbe620f65d5e47e1377b9719d49097d8cb0523014680f87ad91ad0aa27d212b1efeb14c37fe034fd95f3f4c7d602ae3fa6edfdf0e88671e24b415ac905612b396d23d7cc598d2b1a7dfa38ad0bc7063e990893e948	176
6	\\x3c95c41a58c8a084d51e9d2f06885908e4b3bce61dd56080d11e304bc336c21e	\\xa34a030ac60613ebc86de8337101df4af7caf756064bc3fd1b46c9d5afd65b67f4ca804487864cf91e6b0183aee51f6d1571e957a15e8293526fa39ccc2a73a06bc3022fb9446cb09b227f39286af52dd74bc9f20b16bd20a90a451fdb3015c9c7bfb86e6b25ad96bf1290d777b93396fd1816a85e4c6e78905936fa5d56acdd	176
8	\\x705bd41ee54e3f4e5bd5eaff9c83e52fa1db8ddfa2b1ce17879d8bcc789f1875	\\xae68d2c3baaa865fe5b1d075d1ed43ae6d49c6e7f54cc2a47d978d436b49325780fd34bafefb6954f13b074ccb5301276854d092c75e9f160638cb1e6dccd0fb02995a0c21901415d8d51661c19b0dd22a127976cfa411de1b6b56ab9a6cc2c53af3c3812305d1b1fb732b26a97926206e18019a8823f08213be03d20bda3f59	176
9	\\x23696fb8964d35ce8bbbdd6c017a2481c639ed66cccc4c767c5c8c8b6fe0edbb	\\x88319ca57c21bfb99d43b238a1e7479a6d2ffd4770fc32ad0406388be35bdf8689acc92d61995b67a4dc4b2179667c0210ee867fabdfa5bfda8b1504659af10bc97651c992083a1b9cbe6f1cd3a13bb025caf3a3178ac2d926b36a4189045f369a6157f1f002f8eacddf6204870b5c9761b09b524c8097a80884a944f4d2ae5d	176
10	\\x996fc4d96d6d8a6507922f21b786aea5415eef34aa7e061f12f35fecf89167cc	\\x28ea1b1d0f8c82cf5b9c59f25e46bffefb2c3f772716cb863a68bb75743739a3f7ec009b2a0029c10caef543ad4fb6536a5de38cdb369e89aad813b188572456f14d86542bf69556f7394634c132adb432e01b5368c7f17d14ffa461c5ff599e99f97ed9285cf7b331504a207b4202422a19f50c00454c1fa64591cd0486e055	176
11	\\x7a246274c670bd75c5d258d1bf0a6d90a8855ff9c14f134cdb81dbbf83bcad2b	\\x02403e639c6b00bdeac29bbc9888acbd23fefc8c3c7dcfae18f566e1aa01deda891723627b1f1c02934d5b2013a08d4409815c3d27da13470d541df6ae554cd22bfd62c64225b58b6f866fa755134cbce08aa8322000330e6ed67665e3852cd737bca2c2b341b0c8ed00c4827264d6da7eb5da2337c9b2464b75e218792d1c9d	176
12	\\x3cc3a8dafbf7963a8db931adbd1b50b1618b6f24a8b739c4f784c8509921fa26	\\x235b414beab5aa7e62067d1f3012ab8d2dec8df8f59fb363b5fb4a39cec3d192c271690922d1e9d28a3578bb48d6812539a46f1f6fabb69b96bb86ccaf0f83f0e52f7ad580f9d505b6f430e78a3838ed3c060cfcbb676778f3bd97b6cb549de2463b533dbcfbef2bc039331b0ac4d0e5e6528d8a6133e3f06100298233cd73b4	176
13	\\x282c6a6ed13ea735dd8a60ac06c5a59dd80421f401546b83664322b3825aacca	\\x9d71d1a24c60507d93dfe716072c79b3b994b35f10b13e033694ff94ed583f20d1445b9ed03e0e68b6812af671399f540272c8a73dc425315ed6507606db4c23b0e93571df9464153a47517acc787ba50a3f2abd5166eee9b88a6053dc7fa72a218d2f959119be368cc75afea12ffc2232e5c91707cd5ba4ef7c7aaa24b974d7	176
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x6bc2923573f8eca180ad0902041c511b1d9caf2fda212ea7b415e91cf9d6355dde67c85b9357e5155814bc06f8ba53ad16c6ac9ec9ad3ddc013dd7654d0a554c	\\xdd33b87db3fc80cfc511d24ac91740bb55fe2825b234af58c1619d5ce30b9a4e03dbac1c2220ce27358f5eea2ca38999ab4f06c895c2f588877c8cb762850b40	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.011-01KETW7CP9V3G	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303335363134373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303335363134373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22444631393444424b5a33504133303544313431303837324833434553534253465638474a5839584d32514d4853594550364e4558575359384245394e4653384e423041425231515251393954543550364e4a46434b4239585647304b564e5635394d3535414b30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3031312d30314b45545737435039563347222c2274696d657374616d70223a7b22745f6d73223a313631303335353234373030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303335383834373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22595259343041435046374e5352544b4b53355637485a485758375347354a5136504a3830353344383033484d3450514e31384130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e4d304b4435534d5a35475345454a304d514e305957533734474a4442394e564134584353433959393438435945443131353130222c226e6f6e6365223a224454514e4a59525230525935414e523939473036314e53353938523139484e48393835364434375052525933434e363433415647227d	\\x437becca6923b054068edafc1d492e4559beabe044150d618e98ada2d5625b7a411703f0b0080f776f630cd97f10cca868ff0f605f92a0ea656437eba3c4b6c7	1610355247000000	1610358847000000	1610356147000000	t	f	taler://fulfillment-success/thank+you	
2	1	2021.011-03ECCKDCDQHJC	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303335363136333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303335363136333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22444631393444424b5a33504133303544313431303837324833434553534253465638474a5839584d32514d4853594550364e4558575359384245394e4653384e423041425231515251393954543550364e4a46434b4239585647304b564e5635394d3535414b30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3031312d30334543434b44434451484a43222c2274696d657374616d70223a7b22745f6d73223a313631303335353236333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303335383836333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22595259343041435046374e5352544b4b53355637485a485758375347354a5136504a3830353344383033484d3450514e31384130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e4d304b4435534d5a35475345454a304d514e305957533734474a4442394e564134584353433959393438435945443131353130222c226e6f6e6365223a225637594a57385a3042484152504453574a4d59334d44375447474736444b5331364333484630485937575238544e434e56573930227d	\\x8e200743b1f149e4c721696b999cdca799da98b6de07e47f198d734869d0f7987c0338dd68b6b83d62f7487774f06f0cdb2f788ee29bb4af150ff16688f29ba8	1610355263000000	1610358863000000	1610356163000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1610355248000000	\\x89e0876001a110a323e47a140c51c9d11159c4f07c141a7fc00cb361b60a6f93	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\xfc9b83e30374c7a220de87eaa722adfadfdd3fd86242019dcb3368343403ae88e32a79524e476e61281cb6503af8a3cf908e3b0bfb833c3f63c7068c72910e07	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x89128ab141ec2769233f0e0ce4a107dec6123829c2a6dbcad53f5cfb93cf50b7	1624869812000000	1632127412000000	1634546612000000	\\x747f70629d11cd03630d582cb46a25ad29c6bd1ffb3d9af3f291caa816288754463e4a8ca7a31473410e114dfba45080ed5819521572fd85a8f1107205ce2c06
2	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x2f1ad66d443b984c2429bc2d0a681b518e8bb8446f615be13fbb4ba123d8851d	1617612512000000	1624870112000000	1627289312000000	\\x3d699dce76dd6aa4b3a2385194fba10a6e8e1cfda59b80ac093ca3964d569cdb8443b017691cd47b5f5ac8fb19edd65cf8cb0ccce45aaa0575adc691f829f50a
3	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xb6ef81925e17ca49a98b5e6ccc4aa14ace3e903ebcee9037d15e851b2dbdea4c	1639384412000000	1646642012000000	1649061212000000	\\x16745d331f17445cce2aeeaec6850b8a804731f802a2b3f75ff1e4b439b9eeb0193916139def6cf4869621f33252a82345e3dedfbaa90ddff79f8d5a2c0d3305
4	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xdd1496eb43a2f402d47bbab3ac5b77577b8811296e71bf982922f1b2df6cc590	1610355212000000	1617612812000000	1620032012000000	\\x49f150d910c50bc03233735effcc4e5fdb0628d48ca685dcc6e01638ce0595616aa878601ca98b4528be37676a5aa3ef7a717806e344002ad0df72064e256703
5	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\x7daba82bb80d1a43c4980b73b92c2a1bf0e4b34b9c390dd3b2d8494eee116df8	1632127112000000	1639384712000000	1641803912000000	\\x11962974038bf4e4f3215b168db8f6e4cba990294137b38fe91e35e514b1b455f9cfd15a28e9a6cbaac0ed06e7cab7d637d1c6ba195db4d496709cf2e9093508
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xf63c40299679eb9c6a73c97678fe3ce9f302cae6b490028da800e3425af50a14	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x6691a7163323acb95c19e46f0d683dec6150708ef72afde59d6873a7a3fadd5336dc72e009ca380e4cba48db1d4a419f5a1cbad2031b4542b199690848be9101
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xad01369734f961973a40a5ea0f73272424d5a6bb513accb13e4910cf39a10942	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xab5ed9640e037fdbb9aaeae5974b128e2ab3f6b167581321a45ce9d335133416	1
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
2	1	2021.011-03ECCKDCDQHJC	\\x68e3609a97d633f7525b95d60036dc54	\\xc2ebb086b10a8afe8d4200e89408eebaa18e9e1f52e9cec7243f81ccc36021164af618bb99f73694b115e3144530273c5d92e4b7282ad276f44cdaf07844e86e	1610358863000000	1610355263000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303335363136333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303335363136333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22444631393444424b5a33504133303544313431303837324833434553534253465638474a5839584d32514d4853594550364e4558575359384245394e4653384e423041425231515251393954543550364e4a46434b4239585647304b564e5635394d3535414b30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3031312d30334543434b44434451484a43222c2274696d657374616d70223a7b22745f6d73223a313631303335353236333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303335383836333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22595259343041435046374e5352544b4b53355637485a485758375347354a5136504a3830353344383033484d3450514e31384130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e4d304b4435534d5a35475345454a304d514e305957533734474a4442394e564134584353433959393438435945443131353130227d
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

COPY public.recoup (recoup_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, reserve_out_serial_id) FROM stdin;
1	\\x427d1da7706c5a063624ca6d61ba4d8372f4701974af9472de299e06e7ce10ae6e504c21cce98ceb0b1367d3f79029a780cc287a535e5103c2536a7115f8fd00	\\x823e7d0d4b24528e2671441741d218207aad2e22805db9821cdd583d100910d2	2	0	1610355245000000	1	2
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, rrc_serial) FROM stdin;
1	\\xe75045708269ee94c7d038d7656f770a607f3d735d982f5d534d23fa9cf965e6f2f425f3afd1dfd5d26ec8ceb44868778d28cbde7e656074d9b66d7b62a6cd08	\\xfac5fb8af571aa81d04fc473541799e8b0dc229d1acb65003f4fa73e0a75e760	0	10000000	1610960058000000	4	7
3	\\x79dad49f125b9a89b735112b3c80f9e945ef58880889a965a7c17deee89c8490795c48332bb7f11bf77f143f75227c74590c28358cf9bb56453700d8fc67df07	\\x48cf929899185d9777d7cfbc6baecef819c6d8afc7d61ad7d1cde6d425b3a9bf	0	10000000	1610960058000000	6	9
4	\\xe0a86135917bc92502b240206bf40b7a0072f2ba8ddc9933215aa28bff81b9cb73b4fe85dbb41201ff22ec2139df2a1ee1c4a3cdcbba039bf6ac81084be1c803	\\x38f055e27f515b200af140b0ac4c206eb3fdba4cee8382aa2349cf74d42310bb	0	10000000	1610960058000000	8	4
5	\\xf93329d80609422e180e5f2d492f6f1d3bce5b7782bd9faae99529ab1dcf2568d9d0dea98b8613b650fa7102e515a548200ee5a4206f2c0a10cd7a3c46500a06	\\x339156346c01e6c34d9bf8a2dd3fad65d7dd9dee597f2090fc46a5a2676a8632	0	10000000	1610960058000000	9	3
6	\\x357cee0b93d30ae21aa0c44933f1834c0ed9563ee9532abd8cdaf11205b3dd7e67f840d7a53269c632be6e1477b323b0d0d13765186e815ffb3004202459380d	\\x474f432d1b1cc3f1ab93a4124402756822dd2e9f34460447db11fa23ebf449c1	0	10000000	1610960058000000	10	5
7	\\x6aa1b6c5938ad04a419b9d062f52476e45e8f0ecdcecd468ca8bc4050ef9f541d8ef2fccc598409e8af8c0e12de3d9e1d77afd6304adb65d130a62a7b6b7d208	\\x16b104187cba180999ff08a2a98f643b938c830b10eb152de2e89cda4e9b2f01	0	10000000	1610960058000000	11	8
8	\\x7f74acb94fa977fc2dd289a67201fe64fd5189ad5eae2bd9698ab7aecce9fd677911c2d3054a913008c8d05f022d58b5850889affb806d432414aab257a96205	\\x011a8b4ad379718c431a67618893b1ab27d22e933ae402452c6cade759bab560	0	10000000	1610960058000000	12	6
9	\\x9498224c7d4cf593c60a296d55f0a8571e5750ad130ec5dee3d566bcd3e00755201671640bf93db082fcf0fee0a1d86c52d2f977945f844f663cafb0dc273608	\\x1081a312c5879749fbd532c881ddf0e03925a257acd93f43355662a959a86d3c	0	10000000	1610960058000000	13	2
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index, old_known_coin_id) FROM stdin;
1	\\xa0a8208570a2a8c7c124de88ef2f0d94814a45bd6aec113b6c05a96fe26fb197554ff38e68f51fc76c781c46281c89241b434ff9a5d366753ddd8561b0ccef8c	\\xf0fd003ce9846335b97a9918b7451ed6cf461e8a56313b2263d830a995de92e0407b1073d947491501e44d1f0dfebbbf09a2448ffc486097925d1c94fa88ba07	5	0	2	3
2	\\xae23a9531351913b4a4f919f813795e19931897c0e91403744980667b86cb53b168d3a38aecb700ea4e50fa0c2388f2617f6f7032184db4fcedf5e577be2098e	\\x4c620bb00b8d57574c2ae29cde7b3bca9394c93c251af0aefa1f1372fe984eb29e4563dbb2bf4d6f5777bb361e13b9193022ef8fcddc843327d93161a6d2c108	0	79000000	2	3
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial, melt_serial_id) FROM stdin;
0	\\x7a6c812484e2bb22790f5903b9a0e3ad709cf6bf79369e795f8fa847bd7dbf844b9f3178e7baccce2995c3c241b5cf6428a3fd5fe1ff49c091b364906d448f06	\\x344051716447cbb126f461c737e0094451e0e22225ce617f6b99cf453a5afe1d8741ab8891a831ace265be43817d32cb38a714a88898cb23a6b51fee1c174ed8e369930dc861e5898acd411c7323ba4d997a78b5860739ff5cd23e4c5c53e26dc2fe47db8bc063f33c835a56a9beaf02540029680170111916b89c0981f19ca9	\\x0355b2dcc5cc1691bdf42285a89196a6dde755f4e5233b1c08684453b35c285ca4508ac2e5462f619ad88912f9895d854f29ffb0b89b85e8268bbc759d29e5f3	\\x3d330e0beeef8d301e92f1f1fb5af0b3ed51eb5c377b8f79c58abfef5afa58d382f487de8690aec6b6310ac1c5d2d25ccf06171c518922dab0f5dc3139eab317e6051a1fb543302bac203d914be2325177ffc6523ca08b04d3e29fcef683a5fbac99203965b5b395b9415c671926041aac2ce2abe0b3a5a1c4f2a8fe75ba3b1a	1	1	1
1	\\xc52a195ce6b54505faac2b20ab0d19751face4f453b6954d4f87863b0a30138dc1bb821d8af761067f387cc3ad56be864daba0953b87eff410c393250353c504	\\x5df5dc3b0253a82e524817fdc3e2f635742bd9184ca52e4c6eba685c46d9068639791c03c7c0700f5948fd171f6e97b0d409cf42b809fd0277da3159324e2ab9b840ec4179ca673179672590c6c7ad5358258b93632fd86bc8c506bdab4a0a4bf697d59ab877bfc929b3571160f2a7eb66cf98b2402f6d92e47328afa25084ae	\\x4013a80d3a24d907b910a057bf5f511a62913ba7c93c047b2637801b575cb05b02b0b2ed3c638a8af542881ef4c6da93a2f391a6f925edc076b70b600920ca1e	\\x417cf506d2bd29052fe43337ada7d229e229d95dc5b87fd449538c023841057fe7d1b0664ab521b562639a18704bb7e8f549be1fee63a7e345d68e50d31aae9b37a36653586e626150a8240d4a0f4cfa8540727613df935df4d3872e61a77e36100312cbbcfaab2e5a7c68a5bf3fe9009015dfafe2049607638f2c6ffe61c653	2	176	1
2	\\x40cd30d51ef043bc3d46bec0d04cebe663e84166c218a7356d80929f49861491b11f484f742d101ec88de06d82ddfd867a85284fda4ed253529dd998cc55d209	\\x46e33dc17d09319fb570a10705dfe422ec7b8bc170492c5a76102bb76007e7ca10c22a938aff50e8f010c6eb0099aaaf19052bcfe26df212e8d5c0eabab4cb0a7017435a3029ef4441dca3b8ceb8d51a6cbf3a9bba47856c8abc8a6651bba05db398d237008e4015099edd893edac3f92d563b4b1ffb539f3e964042e387c889	\\xa5ba81c7fd21445b3d1620a0cfa1469648c950126c8cc190d8ef37f79ec964b82ec41c431b111473fd4a3a6fc279ee2259d8f3115b51d4f787233ff1f43c9c53	\\x12cb066f556feb8ecb3acaee2ef4b730ef960168879636dba1b90284ec01b2f4cd3db78a4bd36f8949b6543d1462b81f900e7ec0c3e27e3b8ce6adda85148e345288af81bba25be332aa56e2a7d291365661d37a0cd34f8a8f67d63fa3e5dc1cd4f9f9dfb31c190f8cc0fa3335b3207b552ccf8169b9c9b44549cfde43794f1c	3	176	1
3	\\xff00129ff287929bcd642cb8ea47b76e4da80929c6e813573ce0261da74d5078da983a1a895ff33022e7623da6de5198981b3ade649599b8621666746c901802	\\x8db36c8aec0c2e650cf220e6fa9ca63f6bb00e756bb0b6eaae59f35796f45589b40b73b019be97ea09d016e824fb13efd3616d39d8a1906c71166a8e4ef584d4d813a51528eeef8875ba19410cc86192c357c61cdc02249e90c4d8e172629459ebb5d90785f1e3ec16835557a212b69e2d0d6e7c627a17a1cefbb865584e5e87	\\x3eba959cbfeba6ad8cd0ac655e82ad25b4ac2a7799dafb3ba82789fa2167e288ed6a0e1897af0b365f7942c87932c1e36749239468679d2aa1d1a8da2480d18f	\\x46a3a7f7068fef69e84b73bbc335384fe8f4c10af8818176d0d10038eef7596f9d2afad213e8e9680b92ea9046b00d53b697ebeb42595c19e606a4e4417e9d51f2fd6486fc45825304b9bb0b3fd6dcc238ed4986f99c3687ee1b11fde316b7bd6d4018e75b6809caf098784efb8acac734a05d8c333445d6a5f2bfc5d0b30a75	4	176	1
4	\\xd0353d6dc596119627bd89b2379e41c959daae82078f5e7eb55013091f6383abfabdaee9f5dc8843f9e70fad8bdcc2ae14f18afbd5d284984c8af6d1829d050d	\\x88ceac257461ace13fb13a020a471747c636c2ecf876eb895f69c1961f2fc5a8ec84315c3590ec20878f02df5358c73a6d0253d7760bb9c14dec07c6de5095d7b9a4cb083808991690e0496a26fd88165e63ae03f8dba11c67dac1b49af26971f7ef1f14c1b2d7a27bb530704f992a407c139a426eede0aa9397932f43162bec	\\x92f6c5452558a6397c760333da7516cb263047d622f815db137104a4d3f7c66dbc657f4a861de01487ecf38af7bbd914cfff0fa77b5591696050a5ad2945c331	\\x6478d61b25f940d61f3203bad126a7707cbf062f71899282c6981d8267b71674ee70902ed5cbc27977e7dfd5df8929aa50f05d1450af2832fc80c2310836a1297f83b74967bdb3f82a8e4e29351d209cb3a13041d3980d9639b5515969e4613d5d0707941327c80db7e1df2c737eeb0864ef85fbf1d6e56b27a0c13892709ff5	5	176	1
5	\\x96da3cbfaee5c08fda624653a9d83e4aef09908e3a038585d2a01be55b77eed6cfc72ef88b00ff6e5be20c93e29aecf68032daa64f7af0eee1ff1e94bbcbf10b	\\x97efe62f82501b81ff948634ab86214efb5177247345ce3b2682eae1d7b8382a36820b2caa5400887f01340529a17211f8ee3b653760e0da07c24a09c3c7482e750cccb14d08006cbdfacb3b75c060a46d32b48628f4b9edc6db986f7b7d9cfc6bfb71e049627c87239c850ca19b0fdc57dcf85258ec2b6756903399719f40a9	\\x52e85b4c5112fd526fed3fea34e5eb7e0cb28a4ff06dac2c17fd32ac536eb67d5b1d15f48c68debefe93128ecc43f805fde088306bb25a80e76c8db5625242a5	\\x6aa9dd5aee564b35f81e472183914ca7064b21541bbf9541b6b3bc4e7f0a2d5fb518942a39abb5a2baf6207be211afafc6d6c1f6df996cf5baf062b8d4819e270cfceaacb85b78c86213f309d7d118fe6314b9e0dd77c3e9bdeccb96e8dcea94df3541b015d985f2ce8da7c1fce760eb8c1c8cd06f309ca2bda5e799230059bc	6	176	1
6	\\x2cd1d91663a1189d88790e815a8646d0fca3e2aa640c563b24aabbe22e7647095187bb8bcb1f9e21b86eeed74311a409b184bc065c72bb16c6d08fc17a147e02	\\xab83f8320c116a7a1932e6c69a28b5ee445af4b0a542f9b529e8b975369ea78a63292d9729d5dafbb0c686e8bad0ed0325593c846036b0eea26abdbe73746e885b5ad3c0d4cb18ee45351ec4bc9de72c67103be674a60e62882b5285278ab65772baf7b13a2e402588eb291e9a15eb2c86323dd6a67ef5102c929e4c4101ac8b	\\xb87f2f4550a7ba3479e7d6d6a48509f0b01b7574244e34112e105a39ff3598315b8aa1cda9e456abb96fb17979fa28e0bce4a58f4d233752444e7eabd20f1e95	\\xabd10fb00ba4559e52df8e00036e6259b3564a8f904f141cecc09fdb967418824a681ef0095f9fa42a856d55fae15262e6dde6bd18faecedf6b8bebde844d0a75b052945b36d9270e29b00b61bea22c5a58bcca3953f1a69bc530232a0dc74d083294f2ceff7b2d233c0857ee8cfc27933a51c5d11750b6830c9c164c3b9195e	7	176	1
7	\\xfea7cd816797caa0c454073c879b3e2343dda7c4376d22cee9e681b4b1d58859ff6ae7eab5430e029b271069d89654054504a8078d51baf77ea52b3b449c2903	\\x07152936843d4e258b72bada30e479fdb2eba103bb80e0519d1cf8fbf36b532e9a45438854cdbccfe66e97be2309a63195030c0a8377edbdea4549e45a053a72060b408da1d031ac57d1ee59f0652868f1ad44348c1913b947fc4890f908bf845fe17d5192c2bd72e263b3694eef6828870ebd1d55340b1280819bfb9a8d3268	\\x7ca9ea6a0700930d09b4ca11e75672dea0a67a289cba99eab199a1bee6759269746e6ae4359353737f01c000b9edc43f11922aac9e64dba0afaa761cbc89456b	\\x8949c067558992fce8946dc04e3bf180c3f35671be222e8ea65115cfab729638dc553ec6732dc331ae6de217badf24da41455ecb4cb15a57d4dc1ac4c18e1cadbd7a81d2afd709e759179190882c57ae595e2343cec34dd5c6a6b11cf52bffc7eb224c9daf85cd607294df1e61268d1cce46f01ae4d2b39aceb056f5951cadad	8	176	1
8	\\x6267334594a4b397e2c97fe37f938c6248f844980fd45f40f462d6fdae29b7ca52a72c98a9b3c4176242200a96776076b3fb6495ec728422cbe8dffab8cfeb06	\\x6a6d3b2524dff736ecc675a17bf12d3c55154cb96986263566b7c7b7a2999c28edb51cddd18b0c01d2f76d97a471115e23341a712600b73152220152edb2b1782d7b7cc88b82354218b4610654c34fee921e64eb9abbf04ca928dad0092d2eb6a21ea03cc90880627f9a3143491a8a1ed33a86f1f75f92fe2e3db933795e054d	\\x939b3cb647a52b295bd6fb9b34af9fdb1a654ac71f1f3fc9f0bce3572ebd980c4cf22f19445718e86132aad5ed82510ed3a89f82616c34ba9233020a32c5a020	\\x9166580abe2a19e5dc785ae1c80d6462a6a3bd475569aad0b8fdf4c6ec88d9af3d4182e1e1ece70943db54a8e2b6dfdcee2519d74f0820c4e1ab6059f733eae6e4210b27d5d7dbf62ee5705392845b04bdb0a64adddade4431daf885c580d902b45eb09b49fcf9aaae9c08896b97e9ef6b9b4866144d20a3075b1e84c8c54839	9	176	1
9	\\xbbe2f3c252faa6c1e0572f9fee76bdefe3a1a04f0354ffeac8e161cc813bea20154b25c977d1a0dda1d1a6086c9072385629d9cd55f941a989677f396532940e	\\x1b886735f772f9c04903b4d7e1c49a80b8c0de07f13e768df0c30db1df2d03d465cbd593473af3f19d4157589161e740b96f94ea687e52bad3a828aea20e16da15c1c130b8780b9bb58f839da5a5fb5e8f9c01103fa09e0b0612ef3f57a8f7f42cb4ac4dea473ba81e5305d75e1da3409be3625833c5620b63497ba1f1abd67f	\\x205db2e84793975f5c1e28b08f1fb133714ddd7313a4a28eae45c24b32fb4d8a25a2d67042979256babfe2ca55ff0c4d186215fd713e961df20cd2d80e2dcf76	\\x9360c5673d48ef3c684d143a04ba3a7e3fd5523449c09ef66e81ac4915101d8d4dfc3ef9fd044955b4d557928c278e2ee6a38dcf5b76632183ba8a9f85177e97b28d1b28d165a954278cccb489cadb644cdf6bd9a72ba25a8a0317d71792a2cfa32a121b6410767b226a0f8504ba9c315d027ba6d836dde63321e1065c73bc8f	10	361	1
10	\\x34eb5117e7829f0fdb8ce8f9bddc8e8765a9dcd2819bf72ba403d37bc02cbd9728a315adb87db0429100e9be5f6554beb8fbbee762696e716533d3ad8042700f	\\x9a346ead7026b655766153eef2b8f69c5c16c0cca56eb4d6e5a65f1a96ce4a7e3a779001d75d5d0409bd58b17cca150ce057ebaecf65a5153cb2d9cb2dd14bff6ae8b9d3812b57ebca8b04028771323a07b10f4ecb320647e3087ba119a613ac2a87c00f0f6f5430a0c379273a36340680f9641d2e13cf1887e5f4d77e22c9bb	\\x0acccec762115cac29b3cd7a3c6710a5ede04cf8fa76979ac86e4adc22245ec4d15e661dfe9d1d2067a05c38cdb59c633a2640c43c055230978d5c6ac874b3d0	\\x2faa4d21690aa8873e5bcb7900e8d48f1f6da5f80bf8eb0df429ce4481ac6435e368c02432090b64c66300eace3ecda2dd1a9e9e1c05f790a6599441566f5b5f0ec6aa31e45f7023889f4129ef3a6ce2b55464c7b36bacc11b3816b07a2888a1b5c39fc4d7dbf6ec32cb81cd19c31bf030667ac48c57b53ce37e9b87d4fbf6de	11	361	1
11	\\xbe1207953f01f2b96c1b0b4e2b8c04769e8c6575c226821c15e49b7d162d38dc83cf5d3babb02395c8534872bcf107728fad8155c713e96412ca2306515b6a05	\\x3ab7c931c294373c692560418844eb842ee1ec9c7ec43fe897bdfbae775f173fe389ccd7d15d60f912ba49b8eb617229e020272249fa4e54d0553ba9cf582747cba8ba328c72320d8cfd0d16039b2ede934bc95c3179b314fa28e0d52cc9718ef9e28ee39f4c5a9a5ddd93a5d90e4921ec139d11a03f3c0a916798f8ef38556a	\\x827756feff3e35b97c94215b2efcbbadde58967ab64219034dd299d0cbcd859a09dec663ff53cbb439a246557c5ebfcc18a465312c8bb75fb15cb7e38a12c639	\\x18915eef82d95af62574e429c132dfac934f5fe75f12f9ca8fd3335d64d979b4c0ee0c6095a2a7e7c211f8ac8a9b11adc9f94a703c11a7a997f7898f221ddbcab9510f9fd78a8ff976fbee168efea705cf3f2c654e653dc5bdd3519b60031b2e5bb360f30fcc1d8ff91e9090b2974e5e6700594a3704859855297aaeb5060999	12	361	1
0	\\x621ae4d12fb4108689144c8d33f379aa0c7d260442b0c841612021a68a8d208cd1d444c11199b58a78ed1bec6c1f175b44fcad844799f5163bf20f867abf0e01	\\xb6c1d3278dc913edcc3854a1662cc21015a2e6694cabe0de6eff8710168c588623e4dd36c8d3d0aa304bcbbaf4e689c8eccb1f10936067b972c1a55ed820305302d9dcfb50ab21bac97fe17378d2c4db7d7d35ec4d059d49ea87959bb2fbb83192acc75bada98e94a3a51cfc71d68cd82e43963d81039a520e052e61503d1a68	\\x4a8460f38686f917600ac389e0a31d44707e66732d0d3cf15054a9ef1bcd3bd09d4ccc9e58fd198e61a89c6036e7773a5f558e242d8ae92c9dc512825cfff332	\\x7fac91bcac32b5d958279115429a361cc84a229f68444245b964e5f80b830a64839818cb33b8eb7474f9289e33001879e5551a5bd7a9b6b901cd23a981390790d0f0f51682e390e3f514448eb514f273cedf2c4c2229f8cccdd47d505e049743bebbe4d587359f49da278c556cc6fba53791edd65d309e678af9337d907083d3	13	361	2
1	\\x46883c45043b0bf2d1a2043b0cf36bb1e2d934cbfcaca31ac94b06a2c625d44c430aabaa163fedd63511655394f10b84706f0f7ba9054c41b4836681c0903a07	\\x8e850bbda50960ff0283abf1d4ef29df3c242fbe7fe5c3beddd07c22d7b2e8019180363e862c62892b2781fdee35f6a1cade2453632b4ce321ebd74cd7e0435602b00c24f97931712cee8963d935d0c066376a7676539e8cac06b38b8df11f3e3471d162dc660e8d7a5ef7acbff9bf179bbeb3861f863decb04eb78dbcdc146b	\\x46160b04eee208476c965aedcbd4765415fecd243c8c4d7b8655edb7d1aa94ccb1752957658ed38538340fd9c29ec1dc298ca548e0b5dc4dca3213bcb2113678	\\xaebb435b19779c05dcbf99389454bbf537344984aad319eae28e583ab190a96419982c9c8583dec455b913b9f02db7b8a53856c4f53a3fa718d438d9549a54e9de2893d9b822c47e3e35f2d29e80c83430fe62569068364a8ec2d07d08001994bac33b8511a4063a7e888a5c01483e07abdf7f750ce6f3ef31be4c766aa2a1e1	14	361	2
2	\\x5d0e9c5d681fa3dab9d88d3f088c20ce1328f694124ea84e5ad026b0fb87e5238f03d24156d65bd0eeed6bca9389b35c27a2e7a7ce9be3a99a66d1b0d2628e0e	\\x40e1c58d08466c3a96c2cbcdfaa9234b2690cef2e0aa64c76a75b02f7f225f2bbebe6ab5128ecf8353d7e6234ab1315d0879e91f015f7cbfe231f3f288e732e2c8d33416acf2abec128cf3385a600e68fa514b19fb58c73f48694b49f5af6dba49198ce4540d6d80e1a65f8f92948e95e83bc36f9d9f36f941618f1a670af8fc	\\x03f440c2ef9adf4262d4076a6ed6829406aff597a2e5959f4005a0d212d2f7b310fc84c166b9afe3390ba9647bdf7898f767496f2290493def81bb9dc1f2fadd	\\x086e13b38d1fdd954d02829fce3cbc29c078f7e9fd7f6b5aa6fa0aa848cff032282e6a9f344276ea80713f457c6689927b8cdef88542a5ba9b846c4a210b3d2529a69af314fa2d014a259ffa85f3cf1b97c6fa7cc6d45d4c1c303b0e925f1ff16f7a112843a6a461774ef84793748444f9b2bc97fe1af06dc5795a9ac84819ad	15	361	2
3	\\x7baf61d6689207d38b1e178aa4ebc623eb738769fc751a08e07515bae14caa75f2c572405f9c1aba804b90fc247dde1181082f5cb47f0a87b812f35a816db00d	\\x61eb5c57fbc9edcf333829a5daa76dc3e7ede42893d93580fb19af7128eeb0d944698d6c7a70402e6d6b2e0c95f5961901b76a4e15f6578794919f963a9d5fe6cb91eca8850b956d2b0f267c4a8e56c12ac3ce76fb110bb6784e4b83e2f58e32cc2fcbae7b288cf58c5c857c6d1f44a65590c13974b5f4cd40768053ee70de88	\\xe9c4688a5cf75be7159bde79c9d6ad2844438e5acb7efa2f7f0645bf27200d3ac2c894be0834b070f52c406a0fe298fc66502e5a9d9862df685a67a0a184e216	\\x174f92bd5aab0238c1c236eeb1d40d0d30f841482386390a4c639caae2b7ff3ad992f010ee4162930cb4f29b8f96307fbde2025c15dd9a5a4ea19ca289b2d99c2fde04c235c32f771144ecbece09559be1aa0d59b7b1711924f6922dcecd343970cdfab1982a6db9996429963ad08350116ca95f3924417d5edeac5fbbf3f2f7	16	361	2
4	\\xba2c0718449d835a7ed7ac8cb921e296e99831ac70962d4853689f4033e82991da85d7724bf22a180a8f45899814f3a2660693a39aa1a585905e4263ff7ca907	\\xa80680b7f5f20c75c4d2b1434169000a8b4ae919da0876e9501a431b1afc260c9a3cef02b3a8fa97358e9a192aaac546223bdc4a1ca813c17da69ae17655050f556d7537bd3b9b7b47ff798b8428d1a3c397094596aa47b6498273f47cc0e228d1a95b0079b3cef46888df5f085b23277789ca8bf554290799780a06c79b4c20	\\x5ff05f82de46ec646562b6302a00385594f1c1a88ceaead9cd1a809a29168bc97cdde48adb2650d262cac13d8c05ebd415ca8d5190099b17715cd6cd2847c6b0	\\x566efbe8115df7388e921149aae4fa743805d94f935d2b0678d58af6da87958ed2b903feeba55e21ad3d7783739b2b5b82d19a4d242b1df3d57fc63bf1e9ee55414366d0f84c5eec8959a443e91bb6071f27ec125ae26def60a6fe77dc8c8e7cec44b6c1bd0393b6ff5ac89727dd2b33185aeaf55244b00e4deaa1d4b8b19556	17	361	2
5	\\x390dd8f3d46289d4b4d1f2f23ab2eae1050ca4bf4bb4a652f448ca47343baacc927546c1999dff341299c93d79501f7072b82231de69360bdb03fb1a0e15fd0b	\\x4a8e95001ea27a75213f277d080eb5b32e9bc3d181140cedb06b16a54122b1a8232787171e6099b58425fae67009d2c47ea5cf7f160e4f97622a37559df3b6964b9b604c845f43b84b411cd843a4b106245a537f4ece563e67e863e6763fd5c330266795bf79c60ab3c6fca04568a04f95817e8a35364808054db7bebca970c1	\\x9824be5b2d0037006b5d0a76a210e1c2ec375fbb11a73cf0aa0f82791fedeaa841fadc4ef6c593023b4198e30bc390a521b42d7abe07dbcdbcf82cf60fafb86e	\\x94f10416d918bd7ab07eeee60dff8c13d1383f3b3a51bd2fcc3c046c228603bf7cdb05bf822ca3489dc40b62ee92bc1b9ca1859ec73d8f090d33c49f6f7b5230c023bbc50c2b3c8e4ceb1d111c6e1930bc790aadf897ae8d37564f46aa621868564d014dbb1da0de3829c38423a31b8f36d8deaa982993cc57dc2e5ce9c9eea7	18	361	2
6	\\x6e4179a0efa4703c95c690f797247c4b8a11081fc349c053ea56699bf98d65a65eb44a7d6d7145ec1b60325e499fcd12364642474495a0fd6469eb7d1054f90d	\\x7163aa523261207c7a2fee8478fb66fdccef6ce6980944fbfde2a8a1328b1f2b7f4a9276a17d95e6740e62a4d347572160002ea1070143f5cf7e6957ef1334785b13d2012c4552f4520acc57c339ca8e2e80066f91657576cc7b82aaae0c6557a97009c8ba11c4d15382ef2b2b32323e4d621a2a981c0a562e945c801deae9df	\\x5d10efd361fc5969b9e180c4532f3a30dbadeaaac26bc57a1f9c55d398a78ed702ffde6ddf18826572e38f0be75c1779fb6687b11d68630f0c5274a25b175a48	\\xa4a42e009e16a75dd6b43f732b884b0ae88a31b83b679bbee5730dfffa810ddc89b3cbc202e31db366e19b59e220ed0fd3246017af63f622bec9848a2362b2922b85c4b08a28fa93f84b60478206ca41cc4dd7eaa6e4d85f9ca385741709ff52f85f2375a0388b6139ca964dacd03eb810cec7725591aa9f53e743bbbab3da27	19	361	2
7	\\x8d314f3a96d66217a1b2713c202406bfcb1ebb9cd7163c6822aa8a0624b2d05b2a995c5e34c40d95ef6a690aec31b795d6a4150b8207b5c444bc279b3f881906	\\xb05403340bbb2b51c4602cd978bbcf61c9c666cd58dacdcc0eb38bf946a98185a1e81ca7e2b19cbd1ed00821cc10fa88237fab96244971907691c8df61978284fc5cac339b800293c5b716772276ef86c557fd5a2f4be9081246a2b289e343623f1d77f9eafa6965d012d20a57b294569b4c9d692736a7368fe06989caf20470	\\x6afdf3d350f32e6484b7bccf462c844ffaa9ea174b985bad24568a9cdb6b39dff77d33e267717a12849308e1b9381705e7e6a040f38f883092a3ebe360c9a49a	\\x38e02d4f6778df499c02a902969c4d09e6e1379b7a8cd53b917d1e4226ba202c86d493240b518dc6dcfdc0016c305daac4cf7b0934d1aead01833107fb6c5e98499e5925652db0aed5fbff7c361157a07bdbe47d5034b7bd73e9343e10288de6f13f7efe47a113b87535f3f460a270b78ab28f55882a2624ed9c8fe3f24219fc	20	361	2
8	\\x234ba7b9e60c65b0a5c9c1602bd26f075d1e16d392c49d81c98434bcd8cc9fe5e7a2f9c2ac6a88aad1ea7d2dbf179d2f3d00d97be7bccd86f5311ac4214c2a0d	\\x5d0121564ea9ff368578bc1364cd9ea65996d918458fa97c305619e626cebd2f461be2eeca604d030b1a4175a50cd33c4b31ef9bbdb76bbc1a2a6b57dc7f24d475f982396b3e6ff8e7dbe5aba72396baaae1eb87bdf8b7232fe06e9201c2ffe634cd580ebf93ebcd3de92f6affe9eaea127da62d7fb8127a53ed8ba4fb9b5d98	\\x8a5fdfa980f2cd2438adac26d65c1bb4fead71504512ef799f109f2062ae08f3e5699e39337b6c5bfc0d678db3e4d78d3c41e2d0b01795b1a9f0269d89adc394	\\x5e43721c989f7d14780cfb4163fe303cae3cf8a90efafb06642bf4b25652cfc4e970f5de22047892f0106552f42d40265f036b0e300443180b81a15f1104b24fb5cdba51be5d201526a3fbb8a0a211d456e63e35048558629bf03cd93d33c2725dffa7e384a92944e6384134564780e1a5e991acb0f693dfa3143119ac3fe035	21	361	2
9	\\x7e43de9f5bd01a11bcac6b00f4cfd9dcc57860ee96e640441dc63e9aac4b46105e7f829cf701c9535405cb15094a5abfa479c3e894f264321bdeb2e92a3b6a0f	\\x4f569cc8a9efa83bd2c9ced90197bc688204a3e95a3718b2f9f931095f2bbe891ae9d576c5e400553bf3b529a45f87732eb85ff3e3814ec5c4740193316e80e5927e4a632e004f127c0c5182ebe4917fe5b91d1db6b2a52b33b7f1604ba3bece152bcf5a8123b717bd494aea41265408017b0a9f07552a739653809c3a1be5b4	\\x41d275fe09d3633aaff7225519399175257c2d20c009ed79d2a633adebdf41037973bb15ad1c476b2eb8e10625ae6d8754b94ae8690eefec3d01e9bf47d8982a	\\x9c5e3392cb8cd9c9dc8f770359487643004c635de013e9360cee4a46551f7312b2056a1bb808e8ba4051e25526427162b0e43578f9c84c923e838f4132707387e13061dbcb4aa947e3354df51a07fe8c4c894c8459ca2d71e4bc1e46c8d522745be7747634812cf4bc3ed056043fc32cfd85a79f41dad68d8c9c4a8122c84c7a	22	361	2
10	\\xb5100446b6ee04acc3068d7cd4e0850afbfe4185cc8b727420a126239fc0ef78b3a6219dae16a7327d9c3d8da99ccea03ca592a78f66c5c46b4d95dde0982408	\\x9bb202e02ce17fb2c8e124bc79d7b9f33b5f07e42f69f39014607836588e666ec8a965d6f9ca6728d9ef737c042398764e9d47293e9577714b8dea76c49d6d65189ff56c658afcd7858faefb16685be4825be5f5b8856656c4fa9ec0b5a3e12c56e795f2ff9a351cc67f39187c7882b859d03263a2da3afd3d81538ca378229d	\\x37909f35f5314ff99d466fed8b0e2897ee73c9b25102203c4577ff1158972cbf596ece840350cc77c7c993efd9551fca229f9416d38212a584bc1b781939f953	\\x3a9e732c2f534dcb4b6393015168c90439e9c25eacde83484046a341b83a5f955a65e01517d05d97b542550b438efe0c40657a36d357f934bf3655076ae9a603513f12ca46f2c1083c65d3c2075a8c039b6077ac655c080b62fa6575826e6fed18c398feb60e9a4c2449e26ab4893170ad7858466d60cec77083754d518ee57a	23	361	2
11	\\xf75b27c691379f2a8561ee5cf7bda672c421edf3efdd53b420407ef3308e31c317a453f0028818134b5f49f93d02ce20032bde318d70d584c80748b35603bd0f	\\x28f649b7e14ae07bd11d19a5dc74939f941f831ef8763551dd53cac06129d5e3619b870fdb72c8c519bd657a4b251f80ccd1f2baaf6782f21cba4cbed0b7c6ed38ffcdfa54312bc4b242d140b5def2d612b5422274c1ff66b7e4c50b5c25f4eac15dd445e4030e5d9148de13a398620ad1ccaf304158f0d5d31045b8ed834fea	\\x2b0275618ec92fcc80c18f31c894dbc046b398e13f0a44a8abaa53125909f43331d09f1741592e6dddf6de4f93dee273f110b0914c48c89fa509e37a04f8e75f	\\x315a5865c9286263a53b619d2500704166b23709b09017e89a1d2ac2c436c7884ffa50230f0098d6b7da90d31876bd403e0af670ae0cd6405a8f5fbd142c0215d668b835a66a8ef2c1b5b8efc5740ed205a6a7aeb5279836ed19d85011aa0081e543c5fcb1e31bffedb06a3ac78ff24e8a616d1310a5ae58477d4d0580f49012	24	361	2
12	\\x149fbf528e86ab5ae2f7610c60ddaa99f8a13130cf9a57b48d96fc19510a503ca9afa3a01f02c2a4026e48b039a2ee5c1268c946fc8dc022ee3e8e4f805f2b01	\\x63733ae13ad4b9e318d409c0218f665c0b3ab53565ff208592eafc62d0475ea257180b3bd7b25e612c1667e4049f5f42c8958fb18d6cb121b8f85deb600c10219227fdb54219ac60e12e1c953ff3c82b1a09806b18c7a28ea2d1874836b75cedfac74aca208f6d6f39b16e5d9939ca14f98979c82580e9b761c5a9853be114f3	\\x5827b9d479490403f250e719dc072113a62ad7e9deee87f7c2883b83927da97f3528d7c7f2d18c31ac366b9edec5c0f946aa33af72d33723fd09bb2623d98f2b	\\xb143ccbeb7ad890b126c06649ad087f7159a56487aa61deb6b1c118dbfdeaeaa68942a784ed768f72b0aaaf1325d19ef3a15591466bd5878b9d32c72779fcbc4a37f8c79315c93e9dec273467d9547b7263894b85efc9f0b7f2ea7557b0a1f0ec06e8b9b83a8c4f1336105807176671549cc7f00e2bf88e65dfd3cb782a53e2b	25	361	2
13	\\x8ab29deba9d5336938438c8bae45a809d43582be2888c62055f333cf4323b6a3f5e0710295d213a8dd21a8e59f7f5183e0314c2d13d67c6625dbfa7bbcd75104	\\x3256c10b4a549f3a47adc615b82fcae24f0120d8bfcd0ce2e6d6d98508ea19b8ae51faaf32e93adfebe221aac7aecad0e4feaf3d7ac1b6c2fde21420bd13ba9c62113bc5491e7d5182707d3425ed45cd496df765d9d6d842d2ebf422b865c4cf114844865d274ce87351fcb08c20587ae4fd9e944f72bb009457a1b19ff555aa	\\x8d03e0dd131d28a6bd4e643547cce5ca7067a68c4e5340b8d5cef83b6a71b6d4528ad949847d18f3a6bef5764879925ac6b261b571575524d60b597744f7875d	\\x1137f0dd3f76766562c10f05abd1aa50c675681395e314d11191fb36e7f3352fea184a34a5400dd6cb637cfd6f68ebdf32dce86fa955c260d45adefc0ef4bfc0bf58c6e4ddfd05e8ca0bf0b20028fe73ceca801af6d325ce2abe695c23e0e0b8e4da9bc08193406660c24bc970cc4adee3c55882d534608dc7c40cc78c623c22	26	361	2
14	\\x66804ee7948c2228f871a28f172ef4140236cef0c4bb5ca0c84961dff56a6331f0d23e9abd4024c09476397fe8dbdf680b9cd1ae661c2d5ea743dbc203a11205	\\x6d9dbdd3e2fbd5e32016cf51abc85136c2948e530124b8f670bde58cb614d46b5b38ab7d0472b8e8154d976a3150219a44b6ab2a5ad3031e1f0554d3077c35bab71e9d0ac2b4d518b42e5bf5adc0305d347ecd585087f2a3cb0846cf7449c9e587108b17b7993e9a5f65825316429c72af7b063ba16a661b99732671527e3783	\\x3a2c6998478e3b709ebb0cf8b14d4d5d3790e512d9eceb8a5a6a92e5c9d3fb2ce3f784868f3446c98b09b7c3cc147511416a42a057e4202c0523611cd985252c	\\x8dd91698032d2f79db30aa9563de30a62acce8b57d34c0ac1e5fca094b270b68a11a21feacdb7e79f6601116808734ca5c2e6dcd9abf9fba24ef21315b2ebcaa6a5748cccd35bacce81f5c26a7bb5e38e9dc06d4a7cb69a09ff33e174833ea2313547ba429616263e36d95129b38fe0a93e89c5c6a0f682b4e739295ad176d31	27	361	2
15	\\xbe544334f382829a223c95f43ded85cdea2e57bca49c94ef2445ff85ba98a6526051dae24a4809a6de67d74ad12a7617b852b3fb3ec0627256d27ccbf951ed01	\\x7234badbcafbd6e28a9209a02f2593ee69250993f30e1c4ea020f3bfb0685b16b5737ed6615a7a5b071f388d87fdea6cd589ae22d0a629c18a06a4f9b55534a64ec3cc68fe8e09786f3cb7a1552b9ef34bb2eab104c4ee73c98b6395da1f8b46382148682714dd7600a17d66ffe4e8d6c8114f4c0a3a38925bff72c66ca0e388	\\x08b37fb64ee576e58a38005db11ffc273e5a1d485d3434afd2f2606200a7f35f9fe0c2d9f3cc9b43d845a167a66f7c80703359fda882b65ddbc72fa8acef5c72	\\x8d5d0e281550a775b77193ee351594785fcf1ef6fb96f437e05b8f5da9b1ef136288b217e7b0e1fe331a20140e830d10ea64ff784d83df2056babcb4b63100a46d09742eb28c315d1d90dba09330160431c724c26720748cceb494d863a169a5472bbadf980c522b97a5f8aef61f93a22289aa5f0b73fc85516f8ac8b4f3d7a9	28	361	2
16	\\x44f1516a56339bda85f8deadf4acd0bee8498e6ea59f1d7e76410880120095f8e965517e7bf1c18b5fb11bd4610760f4615ddfb11a9f2f8c50c9d49f0f845f0e	\\xa4926aa74c6b7d4288eb848d2782734499349b0adc73a31485cb95eecc98079e219df6ca7306bd2ab333aa07106bacc2c60ccecf097b5b2adb020a5123c5641812d1f2bf126904925e909b2c364b6dd579e9cff49bbb098e0547f56a247ce30b97c20c4d228a10e4a072b8cc0ec792a41afff3858fa4025d250324326880d453	\\x7322048c6c49b3158521882471f0c11e1516a7fed0b1a1dfa76c3590b7f93d671a2636988b64779d0bba7827f3fd6dd445411c493dc001cd0393606fa3f4ce5a	\\x81634f815c464500c5e5d6a70e5c07509efd0e65dd011063a8d5249a05cc4e74957b911a1b8485372f1c0521118c9ac205d07c3de7dc4ddc7a05010fe8f7e864a505f608eb21d94be47f7ab36550aad698d1f16c15b611631cf6b5d8755ba869b8769e0076cd474e795b2de91aed062b540879be1bf9865d91141cf93d90bd14	29	361	2
17	\\x2234515100ed21d8f229b250f2b6a4f6b054abf12e8bdc37d9a4c48244a943278cc6e8e70d7505a992dbfb8eb563a903d0efc82815c254fa507bf1ee0de0200a	\\x0b3e88d4624cf3e12dc3e20d9693d0f849ca3e7b7008f9bf2feb89c7dbc740866d5ff87e0fab7dfd3659a6a34c8e902ce135473dbd906d1451cbcb3b071c72a346c93068b34c59f18ab18121d975a57c2166c3ca8f428a63f909730bd931b7f05b758c37e2ebd734454f867f7696be0389ce4b2e431c14734378b9192f609ccf	\\xa2df5dc442381c9d0c473f295ed0cd7560828d5123887d0611fbfa4b04b802af08a0079cd0e37b326536beb6aa52dc1dcda623c162af4db780c11e10dfedf181	\\x241bdce3b1e90b0721c98afcbbaaee3c584d99808ca8461f9a237ceb4aa32303bcd43e8ff6894c75c75a85614fe660856938a8e0a66ab6baa79711e3b62687fa1ba0b5a549991909c65a75249838a81ab9bbe34202090d26b066f34dfd207ee7754d0a271fc688df2314ddb5bd47528f041fa088074aeb063c1cb71a12018be4	30	361	2
18	\\x2409d1a791ab144c1053df71bfdc0a95aa9d3843b40b5c82656e9117a507e11d74dae369710b8d1ae7d1bcf404a3fc9b3d0628e0ee6125d103db0a46cb805d0a	\\x77df641ab8adfa605aac9754de897fc2ea708ad054051cadc063e07c6ad676edcd1cd5cb0ded5e9abdf79a602a8e5086f3cf0f80e76bef587fd9e8cec6cb74400cce5196f045f231304cad38df31ff70918d9fe7feede529083b4fbec30ce4b9a392c8bd90699b5cb295c9b847123eb2b22fc8a0f357cb01368d6f9de524fd88	\\xaf77e17fea379c851542cf30b960a2ea2b584ad506184f426722007585241a04caa6d144271bc9cdbe2d33675e70e391924c3918c9b15cb88669b7c9e826f383	\\x7b9b85290804209c77abbdec732bcf1920f06572ef2245b5b581a6e549a9355396946217c4787371aa89923bae65c2ce7f2a747db8346cd2da313306324466bea4125cced867b2a11cfd8223c5fcc65c29805c9752310e6745326cd9737561111bd1b286e2a591471b9da6ee9c1292e91168dd7baefdf8de75f0d13923b1998f	31	361	2
19	\\x44fb709d9ba064af5d7210018b2c17fe46c41cb95aa0755133575d00cd912db6c19b45f76c4751915a2b7631c909decea788d503e48471c9dcc5d72a36ce4906	\\x27a25b0e6f2257265f39a6201853594fb697670f61249fc1c32839e8aa46d24d424fb642ccc282acf0f61b867ddc6f8a9dd06ede8abac6b0e7f326b4bd3305e555d1b5e2b9c3e6cd902968b61a7a361de1e706c92a2af36352d5a915198c29663d3e4a4b8e1b969ae5e4320434bbbee129f5d9ac8f449778c46e125beaf90ce8	\\xd9edc7a9679992289131b222ff2489140c771934136738db26d48d1b43fed2f835f2683622e43f271aace1c66a894c2e08a93e86484193a281b678e33654ba0d	\\x475d091a34ef42ea84d4bd14895c78a3cc9ce535f0932088ec7f7843cd7926d4450d0f6ec99be991c1fa5da6af1b22363cc1352f75e7aedb1b104787cd98e678fea1b20d73164dd8c4952ab5e0977ccfaae4396a707de1ea765693418f42aefa2329df5da465f2ac937a495853559cf73fb4f2afcf02350297a92fdaa16dbe35	32	361	2
20	\\xfa70fdc61c4f5b69648e7f4b3c5c08d6450954643c3330f48334bd2c56ad613ece4afecbd07aaff5bab61bbebb0815610ebfaa0ca9f4c94fb9556527691eff05	\\x9ef1968d60494d33d4cd50585b8d6fde20ed3f7b689128545d6ba2047c78f536127d31cda7e6e5c9a8e4a204b546463ebb39294ad1413678269f0dc9f0279198d24ad2e94ddd4ac1ef777e185617ce3255b0e57f76d614b6a41a295c5d28d5678854792263b1f37ba97d6ed627e61bc99d6a7327b8f07b65f302a8aa8fe17d34	\\x9a7c16e6cc422d773b33f09dd21a95bd11107e5720f46a1e11a250de89a50f4874e593414ec063e540b92c1d9a7abdbbf88bdd37aee2c83909c30c2a73231631	\\x8ba81982d514c63b92944a2cdbfabcef5a9bf40dff3750b1a41afce5faa9832f870609d9143b5042e73300a10f341e16324dadd9657df3fdb50b8c0cd9d0b45d70cd4bbbab1e1eb4cf7b8e00de7650d65bafbdcfb5c69b85972418e0ef15b390efc7cb9002c8f9ead215da36f52586dc08dfc2eb3006466770593033e49799f8	33	361	2
21	\\xbc9a1fd38c3b1213f3b629c622c3218820ad9b857c2fa9ff48c59df8f183a54347bb9fd2fc7c43ce3740318f473fae47ae7c4939937e20cb17581ddf82e67d06	\\x12f2931b6d37795b7f0385af642d73f1d03d082dbb9c71a133a1cd3c9438f5f8c9c928e4bcb989c523550aaed1ad7a291445e4dbd90b274305b1892e49becc0a210ffe02a18b602055588efa3202b56fe8a14be19cd7b21b7653f9eab43df0a352eb338b462cd09c117a739a7239f6c043eca1ec16fc3cd5dda1985b1136fcbd	\\x77d941e9e02a5afeed723f8f0d9ff5e3d20ea3b21eb90373cb113129e7b94ae575ee2ec49e44e8c9ed9414c03cc577b4b2ac923a19b7239b40157affdd6bdce0	\\x2dc9cdecdbec28d79a27f64d1eb659e1fe20d569bea9d92726219c22d9f588b9a36d126050c97242f778c3a0a4d412a6d029271b678c846bc67d512eeced33982f177d7be405db17b5202d2951955d01ceb71b34052f76aa5200d8f8a401fb4b280be919b1a39ab122e3c7e267d433f0a6173cef801f8dd411a1f40b0722e36f	34	361	2
22	\\x022411a10207827c23c3b581130c65addbc8359553cd5d26979ca3d9e0e180c3f905c9c0516d70b618e660d4afba5d15af6315148f6c5e7250cbae8ec0c4d105	\\xa871ab16b49d581780248e7f9cc77bcf03e5c7c5166f3e33c48ba5d3911a3849e5f868c508e0e367a6a2170b99ba20c60e2468f6dfd35f262eb416c52ce948dfd1d08003aaa9fad99d75ff0453c67633cd7feec939dbce2f58e74c17b03ad72e8af893ec01709b18f6d1a78183bc490eea36ce6c4a97cc122cbf90f3f1bd290e	\\xd737979436fd1e8cdadfdde018a16a40206f1ab21dbe1ade1a8b41cef977ca7a419789b8a4b5aabfb1106d3a4494828ffb9bad945ebe7d3896ebe52ab1cc138e	\\x76faf66a55c971dfed9fe457257074c51e92beac040867e393a25ca2f4fd3646f37d269a679c4a13ba60a916e448eccf2e2944b12a42828fb17e4d6f86dff0c26916c576943f8930840a66095b789ebd982358912dd54da3addbcf7d50a94b29f7deaeb061af17a87f5652034a69f04311a17f6a6dc80a0c335c6e11a553c40a	35	361	2
23	\\xdfc8e240a01ef860f321d4235d119c46426ea445a0575e10f78506fd71c242020777a09f49b8b310f09674e6627e464b75afc302ee7b3fba0106212b9d8cba0c	\\x58244a3a54d076269b710173e2c061dac76fb0a32b0fcf8203d024a4563fd0d7e2fcabdcfff80667465ec8cc59eb6cfb7f02c2a0f2afde7c2686c0e938ceaff3c1441025b8f3db7a16552881c56454055c5d562db1a0fc05af06f41a5d472e613cc471f7b00e9ff838286fe29fceba5607421bccc04f718aeb74418b77d330b5	\\xca2c797b47ebd49f28c3e770deb4862bb3af719349f8027fe3ab9a1524d2060dd0033657841778bf12a8f3f1f74b5423c3f06e4b33e62ab3d3b2c216c5016ea9	\\xb93b12fd9ac71e212ee08f59243e4bb77ec399de85e01529169b5f035b53c68254677846e89ca9ad6e1f6988a2efef637d1a261a73e0715a34fc1a1a0f9206bb7f2110e3d564ea782e772d1d6ac16eefb423b84b834ba4e5734638826370fbd7c6761585f2ca99d00b2be3446417c7629dcff403026851e02f192d786c79f160	36	361	2
24	\\x5fd3a9792627b8d2c7261701e557f6ed3c611672cd634c1aa54394056f603257beb1b1537fee8a08a165f637ab0f3c2516fb82aed8aa7edfc96c1962b8e7c509	\\x0d7f2c1bc83d6ef420cfad13df4ac442640b8526417e544fba9f1322d20ca5863f93a90d22237da15f02a70307a7e6aab267b166aefcd06de02ab9c112bb46a6cf5c4c827e219023160ddfcb0c5fee2b4ee2614455001f15e9e914d15dfa3273f8780a31ba0192b7a2a688ec3fa9fd9139844c3aa1a245c8a170409d8d90eeab	\\xf471ae78727972cbec1c4a0475c3530a2a7637b9970d0fce5ce8d2e903212d647717841b442ab3711e7cde8e3fdeb5fff11748228a5f5d9c426021b8224deaca	\\x340bb66d437632bd572d2b4f2f223d4fe08fb4c1af13ce523c0f5361a306cc90c804bf52cd7e7a73b89e1e4db8ed718e5b5373255376d9396cf8705ff81fc2874caee688e28e107738c0b64255a4d90d2be5c1a9524fb280904aad0e2399e054d5f2983c7caadf202f7e80f9b7b624f409e2271ce375e7f2a0c63abfe7d14ea3	37	361	2
25	\\xeb8c97e7741cf963edcef9135162cb59363f0bcc01e19e9f13e676513ae881d5448e585e0721e893ea9e3532e5d84a8cb92c512e0b5c3dc23c708614bac90d0a	\\x0bf16d2919cea140efe4105b78cbb309e5612749f347038b8db74c805a640ac47ca106c1262f15d35182fa686df52d8d367879cf7eeb9ff007cfbfd77cf4ba9465e56c9e2657dfd2ff3f71fa7e788dad6fd3f8db3df7e531e1c7b8b8f4cb4db32735432004c5470dd51ab6328f5194edca4616e1bd3fd0061606fd2526844030	\\x423dac111314210fc2638473f256c968477475577c26df27acdd45b2242b9d34319ba923364196ee0dd154ee5d34e93faea19eb8e813bb1037f65d72fb474c0e	\\x090f8489afbf62e85b9edee8c5793a8ab7045d111335a009075dc03835c4ea1666d4d90083c51be5e30c97c520fd367a7a8b806abea1753a9b75c6d584d1ab90ba34a3fe655f27ef6ed8236dc5bb05150c60292376bfeeae41aef4edc6869af62c8e64b1e7b4f00e31c364bc89d877e5055c8071abb118df3dee5264f5132a08	38	361	2
26	\\x60bccd432dd0e97ba0b6d436514f7ffe15347db9949f6e5ba559bd43b185ea92e1fe9b8344ca9abe4a8a32eb802b1e224c15413ec3939a0c5fae5ec2d1548b0f	\\x5057608a08eee52e3be871eb6593b0a909cd94b3c5690f7f5b67e367b55ce23efd7f552a276384a1a278878cf9318b4d969cfe5fd4c9c878720bef0384f89c90e95447be6f99143d47a86f3dc9c19eaf0aa974fcbb7e1dc20bc5ecca06c411ddcb482a6532c0928ed683eb463a11c430dcacfcfdecba86d179db8bd96a87277a	\\x2dcd870489b33a43ef5e12de828d63024ed6cc48a9885652a542b83f564afbb4fed6c1760a01da02241d0ab592a77cf978b855efc53a3d27551a3d77ba786d66	\\x696f147dad11eb342ebc3f8bc61359fd6ec77129acbc5997c5f6bf7436396c454539293d87bde7bdbe10667ac2867439b287b2406b9178734ae5180cf042e9a6f36a76d8c265d6a09c56b68bc5b9f8406a8c6f9fe9021625a24897049a2ec424d28da2df09db8828333802c7a1f08791db822220145cb1c7e567496c6d55757c	39	361	2
27	\\x504d9b876ddbe729ece4697fe9d6190b4a8d55b0b1279463ea50a30eec72a2864ce8637671690b5b603c24e156070f5cdd7a40017c3741d443e4c537c1f5e60e	\\xa8ce11aff32b23b20f47c9eb0826b38c0f2f242a114d74e439e77edae0bb75c6e9fb8f4ef3d04a17a66849419ac0f70b3b0b4ff200a0b0da0b976706946ba1c4152945fe3bf3657dd5964fe11a14e80b5fb7de54459b8cd360fa07b2eb30d9b8dcd44f1c6fe1ad2c242c64a9f7d62e190331a200521d7fb9809ebdc2830331d7	\\xe899e2114eb8ff6c269aae804e45ef3d850c2d302a5befa20614b6f8fad5c43edc19fd703861da2ad0e8d6b5a968fe1f2d8cdc664520ab44cec99030f86b7557	\\xbff7e8a944025c99376b5193f909920de9a91acde0bb9564444a53518cee02bc4f5b6ec1247dc47cf08efc5ac929d24f10973391fc9b2a4d429ab01fba67a0e1061fb72646be0c0fc14314a87f56dc1b8d8c3ceafc6b5077dafd156d5a19022aa61080cb26c1b30ee4511206a907df65340750da301197efded496d89de9fa34	40	361	2
28	\\xd790029b58526c6acbbbe140b515869ef50b03444e314bcb0d4e333ff0392761f9ce866cb5642ae8b679066eaa101fa335f613f3d94c1ef522fd7f4d8119640b	\\xbf271c2610479d2d2694ca28ebe8bc2f3b9b0e0879a24708eb9da99608a98c1db7cac8e794534b8d8d38681ed12bfde2e93c946e7a55c5e3b1a0a03e2b1961a85bb846d9c90037f468b510e80bd35d410c9c5a44ac359084f0babce599c70aa7958789a95fc42037a63b46a0c23b6f3e02ee674fa644f9411aaa267cd330536d	\\xf6226c0b2a97b9a358980d089fabb34ff47f8ab667c1f7ecda1bee1a2d054104156aa3e6f6dcf74a56c134abed3856ef7f3aca79d86492192117afd8acaf25d5	\\x65c16328cabe4a498b776698623067e2d7368abbfb9ca999e556ac5a170c77b2f795c770ebf62b32d6a11b4b1542885bdbf5a07e897eebf51e03dd2d4fcb33d0ea0b1b046b072e972cfbc33d20f1886b36f0667f0c9eaebe5715ef1d27d902776dfb33931a01d485ff4538a4de4b8122e51badf8bac7d36624bfe50ed34ccd85	41	361	2
29	\\x84b16a22eb813a1960ef1d3e3dab254510cff1652228baf774c515de5eb385d1017a36f8979e8d86039c9f06c3a80bfb077f2750e8c62ba1d085ad9b20bf310f	\\x8a67a85ce46edd46880c730d614125aeee2d75d94ee33930ace6f5c6c461c48eb5dffaf7eceb2bdb27eb61a952392193847afaeb52fcadac7a2de00a85e456d4a29fe20db0ad14df803cddaaf39d869cdab45d728a5b619dfafe00110faf5bcd6e504d620389be325911956adb5d6ec69d8b5a11a46ecd5f2a563ee89041296d	\\xc09857fc5fa84b41a40a9a79762f607330348475c33fc4e9243e8fe5ac4ba3584c01ece13596bd811e69dd1ad9e79b54b02de6e4f28349e952afea1738828410	\\x7677f2010cbb4bc950d721ea3acb12b203ae5a6084b93e6c4973eb25ce21893030140eef4463b3715e9dc977e6d3a08dbb17b2bb4978e9881d5b10129ffcf6a55cb7bce81a39f25cc163fe473351464588d752d1091a7e01f6701d865647913678e5087cb8716602ff88c1c9f86d56655130a84f1db110a5374a5b5f38168323	42	361	2
30	\\xc3a874f5d33a826f7208aeb68b4bb0e4c3052805b528a9b4d823a37d1819c3760a9ec86ba7b2754a558ea22e5c14a7a3694d00661e2080d5743c0e49964d970a	\\x4a51502a1fa9afe66527bc3c6a4ab05b00288d9fc34b504438c78c11094accebf7348b9ed6a6f1ad50b45a2602592881f95a0cd3165e399a3d8225dbcaf70867ab58ff42cb6ff88f65e48dee32ecac87f13a950682ee90e48d1dd7b8c5496023b410e6903fadf310e43ae3b0b7a8f958c257003c753580257647244377a44b44	\\x56e7ddac6256e14bad7795f4f83a769fd87946e47159a8217ae2713ba4ecf858b53d41d64b4a28d9ab28e7dc0f2523e22cfb21002de76fabc8841c585dbcbc8d	\\x7e59792ec8823905c4166efbe55f9e9eb77e1644f933c576a05becd627c9d926fdc60ecdae4aa4fa48a8870d91431352df9818b5909b8e420d760e26d0ada1b173e387c7f0ad392a007222955ccc7c524654fa3cd20901ab669846fd3319c259476529757c3469a259a43f97278d8386a07437b290705135fb8b6d73d1ac1027	43	361	2
31	\\xd03dd0dd0418cd6b4cd404ccaeeda06114c3128ed287210e553e2851fae861fa6726e7636a018dba2333c59b0c2b3af83c838f1b296176147d06be0c1817d005	\\xb9808aaf1e351aa36b19f4148dce3e3e4f3c7298bd66a0add6dffa788412842ca1cd182b66dee3fa79bb8a3c0a6c0562e293d207a44fb4afd5ce1bfb0e5e063ce270f93ac23087ea282ee8fb2b3fed1b16c1a423e7f829b07f8bdf5d78281b1aab9c1b367817786d6e57108e4fb74e9e8fa587246471b923e467ddc63e39b2cc	\\xb42c44bdca837daefacd83635f7165421b3c1ec3842425f31367516a24b688ec85f4936ee0c60732974a33ce647d1b216167292b64f5d103244b3c8986dcb2c0	\\x8f554083bda905c75aff3a7c8e6742a5e27b957a5b00bc5c37aabeac69366031821c0fb2651b74284ca5d9ed7b432f7e5be3728780de81a5b147417b729f9f36f9acaf0ed51cec3095410a647fe006f4f2879026a2e909e48d7951d1956f1cfa4f26e67d10ce41e95bf91d9b516c3d50548171f3acb52c06eb3b9e75aec1d3b3	44	361	2
32	\\x0f7d0607a7ca16acb0d3b24001233a600c46956c2d8129a596de37d4cce65ce9f2a19394e879cf80c0149fb63a662d6111039d2d638d347936de667cf377ac04	\\x7feb78f1bcf74a38f944896797c1a569b667500066db4e7ce358c00dd51c2916dee8744d6027947847945dfc2ce198bd6db5fc2636af037099a784cd58f823bbe1eb1990c818493ea83759a39984e56ff903c62a0873da1d331c82d33dc4ac6383307fa7b6ce51bbe5dd52c4cbc5f151425d13a1bfe25f59e1fa4ce55d411809	\\x050fdd00a93af95190e9d94cfed39b8ab9cac018e100dfbfc7242857ce231f386c164b7a6bd477c5e791c6b55b10911d9d970e3d61da49475b78ce9e91ecfb69	\\x1ba26afeb8ec4bc66f1d31cadd093290a2674cc20e495d93a1e6efd243273b5df1177c8838e149a1751eeb83f3c19612f3b71b4596db549ac1f8bc51647f2648858bd46c20c37459343634d13c043ec8fd173fda57e24271cecd63a72fc75c86e163fe2ad907868e28dcde9b7cfe1f1862aee175d7f665ef76bc1095c7fe9712	45	361	2
33	\\x36f8d3710e3335f36ed7a590f9f9ebc4a244e65becd4074d94039ef0a04b706eb94528812a388f02f1f471f0d2dc47a1a8597de693a409a213da1fd18b6c7100	\\xbb66cfb290f6cd5166aaafbc9fcc567148f20c4051a63df9d2291cd849da1574351e0631f18fd8f2895f9883933e984feda1ad018252ee0ea8c04f5ee22ae8059b43d0c922b8c1304d12dd2f0b8ecb1e1c462288f1c9ae70683eafe6d71c37cc2ffc4158ff6b6920f4ee59b176ab496d20bdd082561907167e94bbeb869e89ca	\\xfe7ff3627b9f7c5e14e118c9a4cbbe3ee8358b3a0c5bfd33108c3142dc5ec40fa22f955e41ff1560ad264ce9aa88b40679b73011cdcdcd3bfcac9b4dbf22a354	\\x65f5222ec8beecad3f3973298edcc12d1fe413f5a3c08f68998611dc6e28087a5b88b29ecaf6e1ac598fc78999d533dfda2497d895515b7665ec9e58dc4d1867cd90c88518bfafd533368cdbc2619d74f92f8ceba409037f536f91bca7312121b7e4e420b8bcd833956bfaee606d6ca96bc8c911d1766b45ba12c32911452943	46	361	2
34	\\x6389829d60da1e6b7fdf1b1bbbe2afb3352cb784773b2431c9664767f4226fd9a3ff12aafe35c55097b282603e276cec0c19bab0c2337fadbea8ec03ec056e01	\\x41e618f7203b0b33071efe34f171f28b418a43bc01790607571ce37feede16bd5bca9f7de511c320a594add889df40e92220176ea008ebea0fb89543c6dad58dab77771052f525e904ee7d4de292ec0aa70362c29889da9167e44ec22f1d918a58600d0111119a92fa2afbf488b642387c43df9c868b52a6c3b606a532181b8d	\\xfdcd6c5fa24926aff18d2ab510145b639233292283e8567d0d15280b103a0d19bf5ccc1d0beb2254e6f9787f6061a66a38371d68fb2b07997c3a3fd7453012d4	\\x2165ed189a803173be541f5785614c2baf2325aca4de8b28f000321d0e7781140367cfe3254cfa28f464afede9af8b9619bf05457dd63f890a33b7e3c371bf9f7446d6ebbc740178e1770a3da2f57c115dee06ae46b370e037861ea2e295c15c4c7b3cd28a4d8b5bed9527f9bd04d673342d2f01acad4115f3384177a196fa6c	47	361	2
35	\\x4abba103404571a7e58809e6b320b3d8a68366edd9f373fdfb0a9a9846d266a8595666b290e762f139cc8cae61687762e38232741e5851ccc437fd4f2d842900	\\x9faf42e7b9f8ca60bf9c021cdaca870c96e148a67bfb2cc8ae83d7179a11433e3487ae34b36c2e22ed2cb23017bb686baea4496c1053d7048ab74f68f8bd042c7213d6cd7bff228c52774e49fe9e39c56698352b04f73bc2031e5f448a2a2055c56545793d2dd6b1e24fc7fdf5e8c0989566464f3782a46aa2e5e5d91bcc45bd	\\x65e9abc3d02a907853905ee7de049c400b94a3fe8eb730dece78237e90ffeb07c1d720961f534a04cf60ec58b9e7f9dc67cc94c7122a4b32161aae24eccd2427	\\x3f958b11b76cd1b3edc0d36790b64b79abe513ff6f340e6dcff226e68826c5b885543552912ee1a22ea9edaf5b7691cc761131872503c13c6c417ccb924d92e30f45e810a1c9b08bdddc9d3764fe347f700c1c5f9c83ce03277dbcb812b11b27521afe27e0041b611396101a22048bbf404760e5df05a7804515c3030148c5f4	48	361	2
36	\\xc8f88814510e8962b32c4d6cfd1493a1a655135c9e80b5b1fae7a534b9f71aab27ee2ec39f365d6c850943916beca4607c79989d4ffc7753b8cbcc2ec36a7007	\\x90b8240615db8881335625c330c8718b63fe42623ff64ea4db691a120f9a9cb979c4a0005657e77ab0c9ad1297828ca0b71bdc2ff6827f61ce595bf7ad368d174151e3d16367497c35af6d1750d545a12a2ac33fef429980d77432caf3442c5e079042087e4679c42cf5611f9846e3ab780f265c14e7d00dc440596a808fdf2d	\\x51a33ebe7a87832aa20829deb466707e122ed0504060e9c725e1592d38946482d37e066ccff0bb8ca50b2a93b51fd5cbd03017b232de95bce30eaf38f1e7a7cf	\\x76a17aa2dbf24743eff957b82090b9a993b055026779f616c65400be5f58a022f93d24a9ea681246bf7b78ee746cd516ad0cd9c56d8fe2f346c9831b3b2766d73d4c6b190d10aab56f4aa5cbe533ee8c82894ab650805ad3e842667517c8596fd8ee8c2d149c4d70fa4c17049145045821cd357be22d9183d40c091c63865814	49	361	2
37	\\x1028f21b36aa7c5d6e3fcb1566ea09c14161c8fb28fbaf711e63eb7c436cdcbf2f6d41c0b300aa6d16dc10ffd1122c7ef24aa69faf78d07875c5c8c202632d00	\\xa82782998881cfa08dd408fbf6ee6f14abc770e3325ed8ef321fbc38065cc64728b2858359a7a57ef6a18dd58186d156daf9744398c4926b4b57210b86296a7dcbe2e0e85cf227da057a9bcea9cfd9c7b82c5c6a525f6af4fcf7a8495402d9825b7155933a020f99840d88c4101279d51edc2c40aba8645815dd5626af697b18	\\x39209fe88d74d5ac69d293a5d4296993bf65e632e07b52db01b64ac4c3b83792c56e9254548d2906f0811907ca88964bba88e72ea023d1da4bf1b71b1e5f90f0	\\x73b86edda039d16dbd3e42f5a2e4c73afcfc5adfc64605da4f853bffabd047468b0ebccd7381485a5463e2a059d6415f790297255566163a00b1177c88a345237292ce6a7f4059592746ffeccbb2b1076c36d8e54e1d04ee9dbcb51b3b4f82e8af4fbd4088a4deef2d92150128d222b63cce7444346293f47f417590520e31f3	50	361	2
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (transfer_pub, transfer_privs, rtc_serial, melt_serial_id) FROM stdin;
\\x8a7de49ae13876f441131aebcaa1ff2b71e63ca0156ecf40d739d8156f249d19	\\x9256e69d06175f5fa6c609542a7fdb7e155d46f5b7b7166aa58a077036e9e928cdf0d3302248e4b77e4eb7777536a3aedc82fbc87718d3f0c5293a1dd97765cc	1	1
\\x1530d93a9e27fb459a5aaf2a24d2c3acbab34da9e39179bea3ca9ae40ae45911	\\xe594e8469e6ee7d4fc2f510951e8be1c1797d322f51678f0eac0684b05866db2b84c3517ec29f3ae6433e613d7912bc5d2247da204019644b539b1bb0dd8b435	2	2
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac, deposit_serial_id) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\xcc5b38be76a205205dd1a53078b98e6c3d72398623b053a0968a723fb8582e2d	payto://x-taler-bank/localhost/testuser-nnbJGiz2	0	0	1612774445000000	1831107247000000	1
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
1	2	8	0	payto://x-taler-bank/localhost/testuser-nnbJGiz2	exchange-account-1	1610355237000000	1
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\x394c17f71cac86d59fce8ca2322ead99a63d2672ecce2f28af0bde6bd91d5415953e314bf0131b84824170bcadb340f7c300ef555b21a3168342f29d348bfa21	\\x20dd681019babc0cad17d88625a6acb026ba5010578de150c74e86ce59abed1bf2970e470182f190941e84519d8f21a42c3fadbc3664f30da43684a038bf1961453e5d7521f75b90dae2da694c998917b6a4f24b770554b3b5f65147ee8852361f98118be3de0863cd0a4291a9bff911a253f54dee3337b1e054cd99b7b71990	\\x68c8072874195001f12e03d96095926534f699830916d21eed69e690952761df224b7faaa4060c795c11b15cec0e46ce456c0ec43bc6aa7faf863ab64d0eac04	1610355239000000	5	1000000	1	69
2	\\x8815d70c59626f458063cd8c0af1061d9d87f0fe7d3ac8fdb3a875c64e413579b9b3f958e4cdc55017d1655ba8c2ea5a488dd28726075e352ab4668433c41469	\\x438e6d0996437eb65cead446f67ba3e1fcb180d7532bc87721a07c22016960ab10ec5cbb6d6b0a4d1d0c2f451eecd6e772b3aa41b0b214979264f9e114173602ab8b6143a259fc3e7d1cf2f4956fb67a845f704717ccff39b07bef1d11a485849ebb75955ae00059154deab4d3a8e879d352d43b767b39abfe17b0117831af03	\\x38e11356569fdbb55c597115c985bbcffa78460ef5a928f72de9d67baf0f08f5b2b7c9bd9e6511903783d36470a052e40a4a4c0093c86cec9ed14fa747367e05	1610355239000000	2	3000000	1	189
3	\\x57c18428c4873e83999b9220d1ac4ae91d07758e4410b441592737b16f81075087917fc7d1063e085bddc72e9c6301373fc20bb7049959a64568d4d4aeb5567e	\\x98158d17b10836f6ac14c7c63a40c566c52175b1617422fabfb408c7bc2e7639f6248a7648d12f846a6c806b312eda15547f0aafdd7ac6a5742f7d413836b13c658a6a47ab6500c52895eead99ac121d5dda9f5e4215d155d9bbd69462f4a8544e8e4bcfa7c62e3565eddba6676e1c2cd374560834a0d4432a41e79ab888ecae	\\xd1356072a018dfb06ae1ce8f13748c22f1f0475a613d7b0b1afaf58c4ae0b3920292a3b449305fb78c46406156daf1b0a0970999140cedd5f27e619746107302	1610355239000000	0	11000000	1	216
4	\\x98d6f591f62e1f316ff315f522e763017fbb073edc0067dbdb3cdc4c2522decbbe2b7d5a1be03041e9376c20ea9aa5d848f778e44b5bf47a3fb773e24d592df6	\\x33ffab17da61f9185b8ecfd32a5d23815479c00cdb4e69400135ad754841b3b8fe956d11a8202c9cd51500cd80cdc0fe5a9c48001af27c2a0d5a5fec9e4914afac5b03c811f41db962ea9966308e4f22475398c042fdbb648581c36d17f942d3854758e36d700cad2110e71446b8bb71c44aa6b38179361a9b4a333ea0dccd5b	\\x035affb24d025b11fcfce987c1f86666df1176bb13a960b05988a500469476f2f6d67e94467ab9b2d7a694eabf882a9eb32b2d90dbe7e17df107c442db60f100	1610355240000000	0	11000000	1	216
5	\\x8e67b4df09f87fc9c71ffe989bd4539693f29a9fc75052e651e9fcce5e955016e4c045fbc8aeffbf4be0e96762274db5e2eadeefe255fde7ebb88ff763e3a55a	\\xb7961338a5c30c258f2e7e4b7b0c4d9822e6339a5ae105739953be6a9621a5f4a92053e6b5d48ac8f7990725e6dfa324fe347fd72f7f3bba0d848bde226d0bec42c38cf09727de8c10b943a5bd32528138a7efd131b20296dbebf1bcd894e9978043a540a78081f9194f2d7a86c3e2922f2b5470bcdfe911bfcad3a1893deb76	\\xe30a22cf49fbec36c056039131fc9d710cf864d1398c7cd3cee5afc81f6dea0fb114ad76f178f6c14dc465688c86a684d14151a4ff9562dbf91aa7a4c8ffc905	1610355240000000	0	11000000	1	216
6	\\xca59b65f8e17405fdb8456a6835357abf4641404047b0f578483bd90ccdef8bd94698f2b30e11326f036d248285c3a64c05cbd4d3346fee855d6141c580d6132	\\x30a23909084906789df748ccac5d2062035b1722baec5af111065ca7e37bf721f01bb21aa2960a545c53762dbd52f4ac9654558aa3722ab28ad5d4b9348e5b4de0ef5e04bda5d53d30dcb60007e4c811d1fb58bb6142fb7bbc0cf1882626c2135f5f85da4c0913a41f79be84a17d70221b0dd908eb8a4123a2e962fa2750db56	\\xf78950a084353574f0e9a0c642ec908312ab79b38a45463c5eef66f6bb9a81bd90bea860fc2d4460a211dcfd68ca0ce2ede3a8a0e4b4ba2e67b74b360dfe1f03	1610355240000000	0	11000000	1	216
7	\\xa0bd9e95abc0f6d53abcb66bb7aa609ecc4b4fd944f132ab8ae7f98278fe4e077e74431610dfa4bdcd687f42c9fcaa37f59eb24c80338a637e2121030119f47c	\\x9bf59444cf10b971782387e377b6e829a0928294029ef71c7a085979040c1c91f4a92a6973e3af1f02e4bc42074213e54492e738db6b4d0765ea95217d00cadc5821f268d491065c1f1ab2d88ce3224d65790d5f4220e22bc5902be6961b9805b923f25fc9818e8549fe927bf8da835faee532c76415a9127a5faf109ee653b4	\\xbaa06e78e3c84ec513919c6546388db421c15da72828a45bbb42d31238130513ed83da19e7b8f2465abe25075884734cf08ab86b6b65381b435aed39b4045708	1610355240000000	0	11000000	1	216
8	\\x8c101be8771c4952e3d49b07393c8547c6d6e8af822cf0ea834b9f4dde52c8a90355985fbbbc6bd1d8802cf2227fa823242281ce0a6134a7d354a9f519efdddd	\\x8098d8bfdddaabc485742b5bfc2080976639b6c6d73d3f00ffc129b091b93b793cc9c86b62538e9aa1ef32d45b44e2f1bcd73867dc7659fdf80dce5db7ad6bb5a51ecb89e8da8903b8479a5787495ee8c5f915669abeacb6e409bef251de8e08dcafa8198251274fa2714343395055e3f11fa7daf134ba3f65f37f9bf6f4d1ba	\\x8ffb1929bed37d81a88deb89d328607b6e9d7e143033730947a62fcdd9649b7e141f6851c8fdc4260927a6b5bc0cea25db4ab3cff7e4528f64e2175d2569aa01	1610355240000000	0	11000000	1	216
9	\\x8f07eb75c932ad3c7b0cd7e27eca7a62ecd66bce5c438b7f48e9125ac00005d7500bc1f06d7e888041046f87148a298a10206e434bbaac1c5be62e28faba9b58	\\x3b56c5b66edbf0b15c626e468347e43dba5d322d10d5e8c031b8824ca2495efb8078ce21b0b6a826d35319cbd0f9a256a74c250f0b1f571b00de539403820b30e2bd43938e47475676d2d17ade2777b719f6e7952fd0b68f98ae62b2c14f574c953f86c47b631fc99b0c5c48e18a244cdb4d5a94f5e505af592a4888f95a537e	\\x5478cb0c76fd9db5dd2eeb691bca14628bac8c925ce0a2743cbcdfde872d3d1c4da8180b6023f9270a87d646df060dafb082bb1ec5493ee077af1cf713f1540f	1610355240000000	0	11000000	1	216
10	\\x1e38b5f290790ac6bb2168de40d5c7e9bf60cd2f4a974072d6cfc462d791815326777d9bb8f3ac2c24da4d5e0d3cb5ac000cfb072b6714475035b92c3b7ee942	\\x427158ed93f6d1a8d2509709daa053d94102434059672b0f8e79e85acebcecb7cb958dad980db13dd4c306f4d0a6f349ad5de17b878f46776db527716bbd151d3903aa3efd4506787c2b75d64f108651fbc612d9cd66b44c5ecfec0808b2743dc0e4f2514ca750f3efb03a6cd12334b786dcb1232947e4f7517c7657c14d5c5a	\\x64ac5d0d0e0811cb4a25d72cfe15f9c1bdd808e9012cac90c9c425e70f41218149e025e0eb93b86e9cf31497dc80d4ee63b29a623447e3e29b6751c5dcdd990b	1610355240000000	0	11000000	1	216
11	\\x017f4c629cb54978f3fa8ca32f2af62dccd7e8f50535ee1d1e3afa2c59c056ff1ba028ef88afef554833041f9f2adc689f12c204cc86604fd291cb134dae5bf8	\\x07e180545724c8354a2e468bb06deb326d1d48bda593a087a90c089b3e0403c254678fed45ceaf37bf3182165a51b9cffcc2596bf32cab82b4323c2062c8c09a8d4fa1da3f9d2db6eeeef7cc8f161a4e034a2ad85b5a4a533ad20fa2d2070d57ebc96ebeebde6641a6874203244ca0cc62d51312e781ed718069c8a9bc69fa7c	\\x32811b7c0da1e0264b20e026a5920ac83322322bfb17fac091d23e2b00e72d0044f68fcc0d2a693ee36b8438dc1e2cb79a614ec7524878bbe89a29ef29045703	1610355240000000	0	2000000	1	326
12	\\xb42b059614188bb35672e0185c3e89c826d758fd702dbcbdd5984761e5f9c52bd969daa559bdacaa457150393aba6a099ca981d1d237d64818cba80ab42bc842	\\x82df121f964f925190cf2baead6f7538ea411e91910122dd18e230cfe0c2eb4103633b44819a41fe5575241bd9689d41e26b29f22175a8e843214d4b94ffb36cd90d9266b825263a3cb14b1542ecd1cc0964f2cf6f0cf618189cac34b13c1d6fbff7ebc1f55c4c49dc470b65a8538feb8e31a16acefe3eca8aac8355c25d1830	\\x80739e5ad493c5ad4ce7250d683918999a8e493c627d58fd90ac8c60dd4034f5b603c37fc15f29c6f9b72c779d1cf368f07536721dda44666ccf57370a9d2804	1610355240000000	0	2000000	1	326
13	\\x3f85267c0c9b13c5b8b99af2fbf861132fa5e4033804b0dae1b27be48b63192ab5f5419289310315af67d42b990a5d1edf613cdc05b0b4cd1bda2d9391f0fdd8	\\x73998e509584cd0a896f805d57fec2af977120ed3c54fb19070ff93d2fb7ee9dcffd28b16ab40868a67b104e8eda38ad16f3ef9ac8b7bc29e7a37c79703cb172d741574baaa00813c509a91af53f771097a0efb7b37672d6a204315d5a2c073fe89cc797d5920bb66b55712892347e4c739218436dbc0438221cf4c06da56c10	\\x1591f60c268d66877fc54c876c8cba55434308db80237adc0c3d6c74bb7cf88fbe9c6873afb03d65064b247396e4f8242c99a1261e787dd3534ce7847d08a303	1610355240000000	0	2000000	1	326
14	\\x910ceaca2821b03df8ffafeda5fa7c0fcea1fefa9fead45b2f6167b90e62bd23a358f03344ddc77b8e16cf2385bf798d1d86af2204b7a6de913953b2c1b0b34a	\\x8b1bc054e2be659df13b45da5667b33f1b6e3e37daa284cc3d6987ecf487b7b731bbc1d0f79c44a8b50b7352567fd2a1f8644475efb23757b4045de84e43a09b2372cd3374cf3c89d8c45face86790de65a2915c454730e864cb3af7934be837d82f906d347c752beaad96a8bffffc5eb51210dbcc23745b19cd3f0b10bc732e	\\x955b29399af0ba0e8c99263d24488e79f3095031d9291889979ccda4a2d22eb5543692a185dee05f0725e6b52876f2ae7256ef8d73b07708c87f7ae95f6d7a0f	1610355240000000	0	2000000	1	326
15	\\x211457be91e11858b782238b07a8380b391d65f0123b49550137cdc67ac747582db4843e02f69e9f2bd3c2e7cdd9ad5edc256a0c8b3171cb5cf9864c41288243	\\xd70156e6822e01e696f2b0f940390e3785875091dfb1911df72c08763cd0e57762e1d47ae64a3207ddcd23caa4b7f366526ef0f9f1bf0f39accde584a3aafc8986ff3e44263f87335caaf13116d076134548f87333412e0abcdec8061a19f2353c4cb21c137142052911b263457bb7a52ec03329c8ea73cf3c6b9faf759607f6	\\x5bba3ca79bbb4d574f1b6868d67cc8b3fc40ab233cec5ced750fb4968e76e3b442d0850d60b87a17b7414f1af9f7a9628a0974d7c75e37def630ca34ccd2ec09	1610355246000000	1	2000000	1	33
16	\\x535623752913490be1f67cc3cfcf174bbeaea1de3eab6e6c1cd2de8c85343da3513b72569b3001cd7da21129295fe38946194a342c389fb53c767a9f4c90f6be	\\x3eb5906a5e428d89c2c2dff928a9d5a2724ee90eeceb0bfd54e5c388ea8e8421e3dd5e459d82f44a728616b31f0635f7950bf15fb4dca9479706e607e8f3302640296eec75756e81f0578ba118e51610f301eda92c9a37d57cda9d9c4e116309fdf15e77f80597d074c9ce01171e4a313971cf64ce720e69000bd26818ecfecc	\\xead5c29eca9ca8bb69b1721b666e008bfef80afcd09518852757d81751c499df2282bae144e46d45ea38026f548e6b5bba50875d357d28a05275d6496368270c	1610355246000000	0	11000000	1	216
17	\\xad3912f8e94c5f6521e407119642f84c4bbfb4c524e383e188d496f852e9858c0bc432cebf85c3521d019c789079be82be43b0bcab5f4e0138ca267df6b92754	\\x17df40460e8f9d77df1edc524168582c575fc1623493c36239f576a3edddccbc6978eb1ad665a7ad8ea73a6a182f4f82923af681aca1cce69c6781f2eba258c065ca13606592d85b9bfb915f2c9c6330ad49a01984c1a37d8f6f41f5bf03a3f6bb24051ae2f4e739611d1c3866435336380067240b05b72b64b53962935376e1	\\x66a387880660338eb32932950697bae1dbcc5c8ade0af7b085e4871a821f22981c4dc47c02528f6db8fa04f4e5783750dcefa1aad12b5b6bac85bd4606fe6907	1610355246000000	0	11000000	1	216
18	\\xd8e207cc75294f58587b9249104c2b2ec02ee71e578b3cc57011e0d36a912b283edc91794900ec1752244ccb39c89202b4d4af436246f6a21000f15b766bbe81	\\xc6306a91bf554d65cf2305075aa5c9d9a7b8c81c9204943422a7bc762c12a94d23386d32a0702efc270f078adcd714e23b0b4be067348d7bbbca0c6abf7cd6f7691ef2d295ae5f4e5bdea1eebe7d2de12a8b7e7ce9ee71ebcd494a33bcccc8d6f3b663235b0da8bd3fad75130942c49b71bd161e904eb970126a39f966fb6376	\\x420b41ec07c0cb2c1da69631c98b84f4d179d00dd2edd70271ef8f3fb4e281c151d8e7537c32c767dc0a6ca477bdf03c3dfed2b033ee3444ccdd7815892d8602	1610355246000000	0	11000000	1	216
19	\\xa2ddfdfcebf1eca455ac437d73ad6f7277589b7e24ea1667b1c24b60bb0c66cf99cc2f6502d4a9616efdbd9e53aaa82357b505cd3d22a630bde938c59d6008e6	\\x9402ad6b0cd676151daac73b94eb0190c206676739a01836dc0d38553cb030a1fb3ce8aecdfae886cc356fb5ff849eb1563c219fd25118247df31a558a0ea6ecc150ac848c923086756c651ddaf051f5c507fa290b9d4502a23841930b47d6c26aa7cba184cd54aabcea557b8500796061d9d04464a276c000ea98e27e468c84	\\x86df063653ffbcd8d6c986b358b5d63170735636e29c3e6d90a1e63345c8512935baa1af92247edf607ef766766b25e88c2c263336360ada55d2598d31de2607	1610355246000000	0	11000000	1	216
20	\\xf3dacc38bef30b84a221cb14b2bffa9b90f3aa0a8b1ed2f28a8c5ab56fb45b8d897571dbf78a8a2116a5fe94400454f5c28d4e8a223b15981b34757075257e20	\\x8cbfc8513e17ed9fc8a1abe8b08a985b4ab0c71fb12a18666cef37a1f0148f6d61ee47cdd797af8f67cef6d30d2c49bf95d59c4b485e6f85060188013216d27f425dcf1d41038b0af2cc4ab41d960eea74ea05fbe96e49e58ce79858dd9bcd5cc869818a0c1d7c884d01fd5659ab53b57ec172ada6abde363614c780651ca08a	\\xeec4d36ff997b16dea1d087e3cf0fb4d5c212b2421c707d243237a6e3359e018dc1d22bab684545aef3134e6a851f38e9fc42857b2481d3516e2ce81631cc503	1610355246000000	0	11000000	1	216
21	\\x5db7e2014fdaac49e7c5e751fc06df664678a627362d282732306c5c98e9922347b59eafd00c02f005faa716dcd1a9c4088f257953bbba77456041dcb0198004	\\xab61fa4cb045f75770f248059c1245a8070ab20109f80606abb64343ff6fdcf8e902c4b7f21187fdd43bdb794ef2d61484c04a6c15f8da8d15b84df5a746951d767b298d70133773899cff18176261babc0ecf7a2091907e181f97e6f3a280a5b1d7f7561299b204b39693c8cc24ab3bd972985c5e6e1a665f6371798124dfbb	\\xf284c377353dbaf02d6847c391aca2c397468f0c5c03d7ff3427a75f80dc9df2fd513e4bb1d9aafa7629aee3b6248755c038babb8815979a4c0864f1cb73c204	1610355246000000	0	11000000	1	216
22	\\xa841238566eaa5dc509c4b145836574fc1d239c4fa26b365d88471d7ba05400cc1fa058e702c9f3531b2e6bcf5df1ea5d4d634760ec176e8ba103bef7ea63ace	\\x0aa9a04caefe15008e4e3804b192f78cb84a7746c9482affb3b45bb12675a088af11576b1f8951584cd6048492294513dcd7ae23d7ee9d653da2884b8690ecf738dadf5f339db23833ab10fdd98e652514274f8d92834893f3e875b2d0c818d9fc543d19f1ea4900f5f325250fc18bbaec823ec3933832f44e32dd3c8d72a836	\\xf1db81971534bf00514c4badde79dc4779a42c89cd0bc6c44aa7c45f8f0e0e95d553e571ae6b74365bb01a6b866036a02dc53a21769e1680497e35666f6bbf04	1610355246000000	0	11000000	1	216
23	\\x57644d0d60b322e4372f7b31024cf3238f5eff201a3b8d3e63a983db4b46ba2ddbb15afb7a60cb1c212f27094cc7c83b512d54316905924dd8e56cb932e4fa1a	\\x4be635f03e309680c97adb00e2ccdaa295d9124b9f30c9c8c8a3b96f1c4d6e3768fa18e6420b7d75aa1c3939fa97b03072f8c851518e248f878c0528b83faac3e4a62e32ac9eb0ee3b9862417095951a952a601e26ed93c3fb69e7052cda82099ef66c30d5042a552cb8de7153458698bb2d3c11386601fdb869326e98a67c8c	\\xaf98b8c691a22e499f712994b038ec36ba2d1d5073e7680268e8b3c050c516e711be4aa63e7e6d914e733d1002e7b714e0bd1e0d2fda0b475642e467b9357408	1610355246000000	0	11000000	1	216
24	\\xe7ffccbb9bd98ab3db4d06454a116d841d74fa1e0cb7a4bf630201eeca4f7748c4a5b31e576727f27a3903e8409086eb997b831272ece77bb1401290edec5886	\\x2c7dd5dd5c1b172a0198166c3c66eef935014ae1d5a0087b32fb2061bfc468975b9f5f1f67c436f1c3730e8a042f1fa55659f369629c6316d750f3fbc2cbc0f84f24481569d18e534a6c74ca04a1bde912120c16359418c8b7c04c115a53a2b5544315e30142ffae792d6b092aa0c654a620707ea54c0dbfc70cb43f103b3f38	\\x890345a9328e5a42d4fd5092efb00e88516053f53e62b22c6aad8e5fdd2131c1936aebf55bd4409f23360f085d7a31ff9657ecb6ef61dc6ab47158059a1fb609	1610355246000000	0	2000000	1	326
25	\\xa92e4d70270b345675054adfd4af0feedd21ac37cbd5330c09e39baa870fa079247baba598a0d129260255277160f6dc0591a4fd536699421e03b55966074213	\\x08e1cc453b8ed41d5e79287127af55ce580134219cd29285fc5a2c3a71dbd1e148b13b48199931eeeb9f83caa7c711a0963156278f088b08951478b53dc3410d74ef18919f4625400b2d4b87e8d7f65ee21db32454bd845e5c0345488d73a45a4f9bf0adf5fd46e4e294bd7f10f8e4f50f636ace7f79c79a2f99be2441f53ceb	\\x582628e41f06159ccee2cf3bfde6c226536ba252a2e5455538be9628d0befdb869b82f15a3ba2796e1036a43d8f050f797239fb8ba1a81554aa1e41cf3435605	1610355246000000	0	2000000	1	326
26	\\x2bc1314c7f0ff92a1f7b83995896e6d34899962d3cb696a519ba2ec6ef390b9f0c1786389610bda15b30f38f90a5d3c4b5836e68952ed06ace24fda3f4b13d95	\\x5c957ab9a3140651267c3c29ea0e55b94ae82db9fdaa72299b7f3a1cbcadbab62962d2cce7bedfe6c2c661d5e9bc875ad909054ce34c8dae93272bd7534a983a5dfff1f8f97b2d7dad2e0cab323ba210b7016a8995da9b66dd1d8c646e5a550fe4b09e362a6f4da2c5dcb316e153e9e957134af68e88ec883145ab73d4aab9be	\\xb91d53924aad4623a3a20227e804d5c2d929ff7ba108797804a499ef78a1ea31fbe6e9c348e29d2adb7c8ca3f50caf7f49ea59027ce18aadabaab2bc4849bb03	1610355246000000	0	2000000	1	326
27	\\xd5fc2e5e193339d233d6601a57201337626c8a7a749b218b992c9015faddf66e3cc4f0e02248cf179c48639c91ed09715edfb5406b1bbe1d6cff59fa2206c962	\\x1d9a9024fd02dabe452641fc115fcf44dda5cde21797cb2cc4c794db0c5a8e0beb2f657685e773d88547b5227db3e9d55f7e9ae3bddabafbf0310604692268695c75a1bbac17f4ec85c7c8464c50efe4fe7aaf39e4df65ccee9cc7019c1c44e38bbef633a05b29e3b861696f4ac90989006668a20db6479f1eb3eb81678bf2c0	\\xdffc5dbf336667f3279d14412c6ff6b93b7fe1e61d626ab185871e5bb68f48f08b763b0507a7f8ed4045cc3cab129b4c2e4aef58b783769618b4d0fca91c9806	1610355246000000	0	2000000	1	326
28	\\x3878225a28afb39c53b824db3b827aecc7a8b84512068bb71c747305aebffbb011477ae7def78e13fb343b2635ff83ff29532ea3afff640398014ddc29d02ad6	\\x26643ebb83cf64467e55f219789218b949ea09cef166ce32beff4bfc0c60f3bd178231d9799786844ad5d8c74849806b4b9d6d44e847609b69cbceafd64bffbad3950653c32b0aafd4d7bfc1e0981aa405ef65760516ed2175c6d33faf7c02251e91b4253d4228bef97265ac8d82bd6c9d8189afdb5d7ca71df78a0841e6641c	\\x774daed387ba476d06c800080572c9b19dd0dfae2242156a0f211e9322c32f1b45b48ef81b99b5c77431df84a5217f195b0c01b1824834c90ff6b7e0015fb603	1610355247000000	0	2000000	1	326
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.signkey_revocations (signkey_revocations_serial_id, esk_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\x49469e3b20fdcf3ec9d38b605ef26ebe1bed212f37658d6bdc61e128838c21bac1a55b02ce03de76bc4511cfdeadf369e41a8687957b9c36a64861b32736f808	t	1610355219000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x6691a7163323acb95c19e46f0d683dec6150708ef72afde59d6873a7a3fadd5336dc72e009ca380e4cba48db1d4a419f5a1cbad2031b4542b199690848be9101	1
\.


--
-- Data for Name: wire_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out (wireout_uuid, execution_date, wtid_raw, wire_target, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 13, true);


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
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.work_shards_shard_serial_id_seq', 1, false);


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
-- Name: refresh_revealed_coins refresh_revealed_coins_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rtc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rtc_serial_key UNIQUE (rtc_serial);


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
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (esk_serial);


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
-- Name: work_shards work_shards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: work_shards work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


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
-- Name: work_shards_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX work_shards_index ON public.work_shards USING btree (job_name, completed, last_attempt);


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
-- Name: deposits deposits_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


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
-- Name: recoup recoup_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: recoup_refresh recoup_refresh_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: recoup_refresh recoup_refresh_rrc_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_rrc_serial_fkey FOREIGN KEY (rrc_serial) REFERENCES public.refresh_revealed_coins(rrc_serial) ON DELETE CASCADE;


--
-- Name: recoup recoup_reserve_out_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_reserve_out_serial_id_fkey FOREIGN KEY (reserve_out_serial_id) REFERENCES public.reserves_out(reserve_out_serial_id) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_known_coin_id_fkey FOREIGN KEY (old_known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_melt_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_melt_serial_id_fkey FOREIGN KEY (melt_serial_id) REFERENCES public.refresh_commitments(melt_serial_id) ON DELETE CASCADE;


--
-- Name: refresh_transfer_keys refresh_transfer_keys_melt_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_melt_serial_id_fkey FOREIGN KEY (melt_serial_id) REFERENCES public.refresh_commitments(melt_serial_id) ON DELETE CASCADE;


--
-- Name: refunds refunds_deposit_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_deposit_serial_id_fkey FOREIGN KEY (deposit_serial_id) REFERENCES public.deposits(deposit_serial_id) ON DELETE CASCADE;


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
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES public.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

