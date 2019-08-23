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
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: get_chan_id(bytea); Type: FUNCTION; Schema: public; Owner: grothoff
--

CREATE FUNCTION public.get_chan_id(bytea) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$SELECT id FROM channels WHERE pub_key=$1;$_$;


ALTER FUNCTION public.get_chan_id(bytea) OWNER TO grothoff;

--
-- Name: get_slave_id(bytea); Type: FUNCTION; Schema: public; Owner: grothoff
--

CREATE FUNCTION public.get_slave_id(bytea) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$SELECT id FROM slaves WHERE pub_key=$1;$_$;


ALTER FUNCTION public.get_slave_id(bytea) OWNER TO grothoff;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea
);


ALTER TABLE public.aggregation_tracking OWNER TO grothoff;

--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.aggregation_tracking_aggregation_serial_id_seq OWNER TO grothoff;

--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq OWNED BY public.aggregation_tracking.aggregation_serial_id;


--
-- Name: app_bankaccount; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.app_bankaccount (
    is_public boolean NOT NULL,
    debit boolean NOT NULL,
    account_no integer NOT NULL,
    user_id integer NOT NULL,
    amount character varying NOT NULL
);


ALTER TABLE public.app_bankaccount OWNER TO grothoff;

--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.app_bankaccount_account_no_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.app_bankaccount_account_no_seq OWNER TO grothoff;

--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.app_bankaccount_account_no_seq OWNED BY public.app_bankaccount.account_no;


--
-- Name: app_banktransaction; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.app_banktransaction (
    id integer NOT NULL,
    subject character varying(200) NOT NULL,
    date timestamp with time zone NOT NULL,
    credit_account_id integer NOT NULL,
    debit_account_id integer NOT NULL,
    amount character varying NOT NULL,
    cancelled boolean NOT NULL
);


ALTER TABLE public.app_banktransaction OWNER TO grothoff;

--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.app_banktransaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.app_banktransaction_id_seq OWNER TO grothoff;

--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.app_banktransaction_id_seq OWNED BY public.app_banktransaction.id;


--
-- Name: auditor_balance_summary; Type: TABLE; Schema: public; Owner: grothoff
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
    loss_frac integer NOT NULL
);


ALTER TABLE public.auditor_balance_summary OWNER TO grothoff;

--
-- Name: auditor_denomination_pending; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_denomination_pending (
    denom_pub_hash bytea NOT NULL,
    denom_balance_val bigint NOT NULL,
    denom_balance_frac integer NOT NULL,
    num_issued bigint NOT NULL,
    denom_risk_val bigint NOT NULL,
    denom_risk_frac integer NOT NULL,
    payback_loss_val bigint NOT NULL,
    payback_loss_frac integer NOT NULL
);


ALTER TABLE public.auditor_denomination_pending OWNER TO grothoff;

--
-- Name: auditor_denominations; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.auditor_denominations OWNER TO grothoff;

--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.auditor_exchange_signkeys OWNER TO grothoff;

--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


ALTER TABLE public.auditor_exchanges OWNER TO grothoff;

--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.auditor_historic_denomination_revenue OWNER TO grothoff;

--
-- Name: auditor_historic_ledger; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_historic_ledger (
    master_pub bytea,
    purpose character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_historic_ledger OWNER TO grothoff;

--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_historic_reserve_summary (
    master_pub bytea,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


ALTER TABLE public.auditor_historic_reserve_summary OWNER TO grothoff;

--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_predicted_result OWNER TO grothoff;

--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_aggregation OWNER TO grothoff;

--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_payback_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_coin OWNER TO grothoff;

--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_deposit_confirmation OWNER TO grothoff;

--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_reserve OWNER TO grothoff;

--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_reserve_balance (
    master_pub bytea,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_reserve_balance OWNER TO grothoff;

--
-- Name: auditor_reserves; Type: TABLE; Schema: public; Owner: grothoff
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
    CONSTRAINT auditor_reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


ALTER TABLE public.auditor_reserves OWNER TO grothoff;

--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auditor_reserves_auditor_reserves_rowid_seq OWNER TO grothoff;

--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq OWNED BY public.auditor_reserves.auditor_reserves_rowid;


--
-- Name: auditor_wire_fee_balance; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_wire_fee_balance (
    master_pub bytea,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_wire_fee_balance OWNER TO grothoff;

--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(80) NOT NULL
);


ALTER TABLE public.auth_group OWNER TO grothoff;

--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_group_id_seq OWNER TO grothoff;

--
-- Name: auth_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_group_id_seq OWNED BY public.auth_group.id;


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_group_permissions (
    id integer NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_group_permissions OWNER TO grothoff;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_group_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_group_permissions_id_seq OWNER TO grothoff;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_group_permissions_id_seq OWNED BY public.auth_group_permissions.id;


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


ALTER TABLE public.auth_permission OWNER TO grothoff;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_permission_id_seq OWNER TO grothoff;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_permission_id_seq OWNED BY public.auth_permission.id;


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(30) NOT NULL,
    last_name character varying(30) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


ALTER TABLE public.auth_user OWNER TO grothoff;

--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_user_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


ALTER TABLE public.auth_user_groups OWNER TO grothoff;

--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_user_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_groups_id_seq OWNER TO grothoff;

--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_user_groups_id_seq OWNED BY public.auth_user_groups.id;


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_id_seq OWNER TO grothoff;

--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_user_id_seq OWNED BY public.auth_user.id;


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_user_user_permissions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_user_user_permissions OWNER TO grothoff;

--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_user_user_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_user_permissions_id_seq OWNER TO grothoff;

--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_user_user_permissions_id_seq OWNED BY public.auth_user_user_permissions.id;


SET default_with_oids = true;

--
-- Name: channels; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.channels (
    id integer NOT NULL,
    pub_key bytea NOT NULL,
    max_state_message_id bigint,
    state_hash_message_id bigint,
    CONSTRAINT channels_pub_key_check CHECK ((length(pub_key) = 32))
);


ALTER TABLE public.channels OWNER TO grothoff;

--
-- Name: channels_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.channels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_id_seq OWNER TO grothoff;

--
-- Name: channels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.channels_id_seq OWNED BY public.channels.id;


SET default_with_oids = false;

--
-- Name: denomination_revocations; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denom_pub_hash bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


ALTER TABLE public.denomination_revocations OWNER TO grothoff;

--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.denomination_revocations_denom_revocations_serial_id_seq OWNER TO grothoff;

--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq OWNED BY public.denomination_revocations.denom_revocations_serial_id;


--
-- Name: denominations; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.denominations OWNER TO grothoff;

--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    "timestamp" bigint NOT NULL,
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


ALTER TABLE public.deposit_confirmations OWNER TO grothoff;

--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.deposit_confirmations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.deposit_confirmations_serial_id_seq OWNER TO grothoff;

--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.deposit_confirmations_serial_id_seq OWNED BY public.deposit_confirmations.serial_id;


--
-- Name: deposits; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.deposits (
    deposit_serial_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
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


ALTER TABLE public.deposits OWNER TO grothoff;

--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.deposits_deposit_serial_id_seq OWNER TO grothoff;

--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.deposits_deposit_serial_id_seq OWNED BY public.deposits.deposit_serial_id;


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


ALTER TABLE public.django_content_type OWNER TO grothoff;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.django_content_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.django_content_type_id_seq OWNER TO grothoff;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.django_content_type_id_seq OWNED BY public.django_content_type.id;


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.django_migrations (
    id integer NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


ALTER TABLE public.django_migrations OWNER TO grothoff;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.django_migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.django_migrations_id_seq OWNER TO grothoff;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.django_migrations_id_seq OWNED BY public.django_migrations.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


ALTER TABLE public.django_session OWNER TO grothoff;

--
-- Name: exchange_wire_fees; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.exchange_wire_fees (
    exchange_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT exchange_wire_fees_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT exchange_wire_fees_exchange_sig_check CHECK ((length(exchange_sig) = 64)),
    CONSTRAINT exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64))
);


ALTER TABLE public.exchange_wire_fees OWNER TO grothoff;

--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.known_coins (
    coin_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


ALTER TABLE public.known_coins OWNER TO grothoff;

--
-- Name: kyc_events; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.kyc_events (
    merchant_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL
);


ALTER TABLE public.kyc_events OWNER TO grothoff;

--
-- Name: kyc_events_merchant_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.kyc_events_merchant_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.kyc_events_merchant_serial_id_seq OWNER TO grothoff;

--
-- Name: kyc_events_merchant_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.kyc_events_merchant_serial_id_seq OWNED BY public.kyc_events.merchant_serial_id;


--
-- Name: kyc_merchants; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.kyc_merchants (
    merchant_serial_id bigint NOT NULL,
    kyc_checked boolean DEFAULT false NOT NULL,
    payto_url character varying NOT NULL,
    general_id character varying NOT NULL
);


ALTER TABLE public.kyc_merchants OWNER TO grothoff;

--
-- Name: kyc_merchants_merchant_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.kyc_merchants_merchant_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.kyc_merchants_merchant_serial_id_seq OWNER TO grothoff;

--
-- Name: kyc_merchants_merchant_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.kyc_merchants_merchant_serial_id_seq OWNED BY public.kyc_merchants.merchant_serial_id;


SET default_with_oids = true;

--
-- Name: membership; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.membership (
    channel_id bigint NOT NULL,
    slave_id bigint NOT NULL,
    did_join integer NOT NULL,
    announced_at bigint NOT NULL,
    effective_since bigint NOT NULL,
    group_generation bigint NOT NULL
);


ALTER TABLE public.membership OWNER TO grothoff;

SET default_with_oids = false;

--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_contract_terms (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    row_id bigint NOT NULL,
    paid boolean DEFAULT false NOT NULL,
    last_session_id character varying DEFAULT ''::character varying NOT NULL,
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT merchant_contract_terms_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


ALTER TABLE public.merchant_contract_terms OWNER TO grothoff;

--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.merchant_contract_terms_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.merchant_contract_terms_row_id_seq OWNER TO grothoff;

--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.merchant_contract_terms_row_id_seq OWNED BY public.merchant_contract_terms.row_id;


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_deposits (
    h_contract_terms bytea NOT NULL,
    merchant_pub bytea NOT NULL,
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
    signkey_pub bytea NOT NULL,
    exchange_proof bytea NOT NULL,
    CONSTRAINT merchant_deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT merchant_deposits_signkey_pub_check CHECK ((length(signkey_pub) = 32))
);


ALTER TABLE public.merchant_deposits OWNER TO grothoff;

--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_orders (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_orders_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


ALTER TABLE public.merchant_orders OWNER TO grothoff;

--
-- Name: merchant_proofs; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_proofs (
    exchange_url character varying NOT NULL,
    wtid bytea NOT NULL,
    execution_time bigint NOT NULL,
    signkey_pub bytea NOT NULL,
    proof bytea NOT NULL,
    CONSTRAINT merchant_proofs_signkey_pub_check CHECK ((length(signkey_pub) = 32)),
    CONSTRAINT merchant_proofs_wtid_check CHECK ((length(wtid) = 32))
);


ALTER TABLE public.merchant_proofs OWNER TO grothoff;

--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_refunds (
    rtransaction_id bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    reason character varying NOT NULL,
    refund_amount_val bigint NOT NULL,
    refund_amount_frac integer NOT NULL,
    refund_fee_val bigint NOT NULL,
    refund_fee_frac integer NOT NULL,
    CONSTRAINT merchant_refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_refunds_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


ALTER TABLE public.merchant_refunds OWNER TO grothoff;

--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.merchant_refunds_rtransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.merchant_refunds_rtransaction_id_seq OWNER TO grothoff;

--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.merchant_refunds_rtransaction_id_seq OWNED BY public.merchant_refunds.rtransaction_id;


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tip_pickups (
    tip_id bytea NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


ALTER TABLE public.merchant_tip_pickups OWNER TO grothoff;

--
-- Name: merchant_tip_reserve_credits; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tip_reserve_credits (
    reserve_priv bytea NOT NULL,
    credit_uuid bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserve_credits_credit_uuid_check CHECK ((length(credit_uuid) = 64)),
    CONSTRAINT merchant_tip_reserve_credits_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


ALTER TABLE public.merchant_tip_reserve_credits OWNER TO grothoff;

--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_priv bytea NOT NULL,
    expiration bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


ALTER TABLE public.merchant_tip_reserves OWNER TO grothoff;

--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tips (
    reserve_priv bytea NOT NULL,
    tip_id bytea NOT NULL,
    exchange_url character varying NOT NULL,
    justification character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    left_val bigint NOT NULL,
    left_frac integer NOT NULL,
    CONSTRAINT merchant_tips_reserve_priv_check CHECK ((length(reserve_priv) = 32)),
    CONSTRAINT merchant_tips_tip_id_check CHECK ((length(tip_id) = 64))
);


ALTER TABLE public.merchant_tips OWNER TO grothoff;

--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_transfers (
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    wtid bytea NOT NULL,
    CONSTRAINT merchant_transfers_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


ALTER TABLE public.merchant_transfers OWNER TO grothoff;

SET default_with_oids = true;

--
-- Name: messages; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.messages (
    channel_id bigint NOT NULL,
    hop_counter integer NOT NULL,
    signature bytea,
    purpose bytea,
    fragment_id bigint NOT NULL,
    fragment_offset bigint NOT NULL,
    message_id bigint NOT NULL,
    group_generation bigint NOT NULL,
    multicast_flags integer NOT NULL,
    psycstore_flags integer NOT NULL,
    data bytea,
    CONSTRAINT messages_purpose_check CHECK ((length(purpose) = 8)),
    CONSTRAINT messages_signature_check CHECK ((length(signature) = 64))
);


ALTER TABLE public.messages OWNER TO grothoff;

SET default_with_oids = false;

--
-- Name: payback; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.payback (
    payback_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_coin_sig_check CHECK ((length(coin_sig) = 64))
);


ALTER TABLE public.payback OWNER TO grothoff;

--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.payback_payback_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.payback_payback_uuid_seq OWNER TO grothoff;

--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.payback_payback_uuid_seq OWNED BY public.payback.payback_uuid;


--
-- Name: payback_refresh; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.payback_refresh (
    payback_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


ALTER TABLE public.payback_refresh OWNER TO grothoff;

--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.payback_refresh_payback_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.payback_refresh_payback_refresh_uuid_seq OWNER TO grothoff;

--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.payback_refresh_payback_refresh_uuid_seq OWNED BY public.payback_refresh.payback_refresh_uuid;


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    type text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);


ALTER TABLE public.prewire OWNER TO grothoff;

--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.prewire_prewire_uuid_seq OWNER TO grothoff;

--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.prewire_prewire_uuid_seq OWNED BY public.prewire.prewire_uuid;


--
-- Name: refresh_commitments; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.refresh_commitments OWNER TO grothoff;

--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.refresh_commitments_melt_serial_id_seq OWNER TO grothoff;

--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.refresh_commitments_melt_serial_id_seq OWNED BY public.refresh_commitments.melt_serial_id;


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.refresh_revealed_coins (
    rc bytea NOT NULL,
    newcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


ALTER TABLE public.refresh_revealed_coins OWNER TO grothoff;

--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.refresh_transfer_keys (
    rc bytea NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


ALTER TABLE public.refresh_transfer_keys OWNER TO grothoff;

--
-- Name: refunds; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.refunds OWNER TO grothoff;

--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.refunds_refund_serial_id_seq OWNER TO grothoff;

--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.refunds_refund_serial_id_seq OWNED BY public.refunds.refund_serial_id;


--
-- Name: reserves; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.reserves OWNER TO grothoff;

--
-- Name: reserves_close; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.reserves_close OWNER TO grothoff;

--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reserves_close_close_uuid_seq OWNER TO grothoff;

--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.reserves_close_close_uuid_seq OWNED BY public.reserves_close.close_uuid;


--
-- Name: reserves_in; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.reserves_in (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bytea NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
);


ALTER TABLE public.reserves_in OWNER TO grothoff;

--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reserves_in_reserve_in_serial_id_seq OWNER TO grothoff;

--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.reserves_in_reserve_in_serial_id_seq OWNED BY public.reserves_in.reserve_in_serial_id;


--
-- Name: reserves_out; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.reserves_out OWNER TO grothoff;

--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reserves_out_reserve_out_serial_id_seq OWNER TO grothoff;

--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.reserves_out_reserve_out_serial_id_seq OWNED BY public.reserves_out.reserve_out_serial_id;


SET default_with_oids = true;

--
-- Name: slaves; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.slaves (
    id integer NOT NULL,
    pub_key bytea NOT NULL,
    CONSTRAINT slaves_pub_key_check CHECK ((length(pub_key) = 32))
);


ALTER TABLE public.slaves OWNER TO grothoff;

--
-- Name: slaves_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.slaves_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.slaves_id_seq OWNER TO grothoff;

--
-- Name: slaves_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.slaves_id_seq OWNED BY public.slaves.id;


--
-- Name: state; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.state (
    channel_id bigint NOT NULL,
    name text NOT NULL,
    value_current bytea,
    value_signed bytea
);


ALTER TABLE public.state OWNER TO grothoff;

--
-- Name: state_sync; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.state_sync (
    channel_id bigint NOT NULL,
    name text NOT NULL,
    value bytea
);


ALTER TABLE public.state_sync OWNER TO grothoff;

SET default_with_oids = false;

--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_timestamp bigint NOT NULL,
    wire_in_off bytea,
    wire_out_off bytea
);


ALTER TABLE public.wire_auditor_progress OWNER TO grothoff;

--
-- Name: wire_fee; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.wire_fee OWNER TO grothoff;

--
-- Name: wire_out; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.wire_out OWNER TO grothoff;

--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.wire_out_wireout_uuid_seq OWNER TO grothoff;

--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.wire_out_wireout_uuid_seq OWNED BY public.wire_out.wireout_uuid;


--
-- Name: aggregation_tracking aggregation_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking ALTER COLUMN aggregation_serial_id SET DEFAULT nextval('public.aggregation_tracking_aggregation_serial_id_seq'::regclass);


--
-- Name: app_bankaccount account_no; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount ALTER COLUMN account_no SET DEFAULT nextval('public.app_bankaccount_account_no_seq'::regclass);


--
-- Name: app_banktransaction id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction ALTER COLUMN id SET DEFAULT nextval('public.app_banktransaction_id_seq'::regclass);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: auth_group id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group ALTER COLUMN id SET DEFAULT nextval('public.auth_group_id_seq'::regclass);


--
-- Name: auth_group_permissions id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_group_permissions_id_seq'::regclass);


--
-- Name: auth_permission id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission ALTER COLUMN id SET DEFAULT nextval('public.auth_permission_id_seq'::regclass);


--
-- Name: auth_user id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user ALTER COLUMN id SET DEFAULT nextval('public.auth_user_id_seq'::regclass);


--
-- Name: auth_user_groups id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups ALTER COLUMN id SET DEFAULT nextval('public.auth_user_groups_id_seq'::regclass);


--
-- Name: auth_user_user_permissions id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_user_user_permissions_id_seq'::regclass);


--
-- Name: channels id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.channels ALTER COLUMN id SET DEFAULT nextval('public.channels_id_seq'::regclass);


--
-- Name: denomination_revocations denom_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations ALTER COLUMN denom_revocations_serial_id SET DEFAULT nextval('public.denomination_revocations_denom_revocations_serial_id_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('public.deposit_confirmations_serial_id_seq'::regclass);


--
-- Name: deposits deposit_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits ALTER COLUMN deposit_serial_id SET DEFAULT nextval('public.deposits_deposit_serial_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_content_type ALTER COLUMN id SET DEFAULT nextval('public.django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_migrations ALTER COLUMN id SET DEFAULT nextval('public.django_migrations_id_seq'::regclass);


--
-- Name: kyc_events merchant_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_events ALTER COLUMN merchant_serial_id SET DEFAULT nextval('public.kyc_events_merchant_serial_id_seq'::regclass);


--
-- Name: kyc_merchants merchant_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_merchants ALTER COLUMN merchant_serial_id SET DEFAULT nextval('public.kyc_merchants_merchant_serial_id_seq'::regclass);


--
-- Name: merchant_contract_terms row_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms ALTER COLUMN row_id SET DEFAULT nextval('public.merchant_contract_terms_row_id_seq'::regclass);


--
-- Name: merchant_refunds rtransaction_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN rtransaction_id SET DEFAULT nextval('public.merchant_refunds_rtransaction_id_seq'::regclass);


--
-- Name: payback payback_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback ALTER COLUMN payback_uuid SET DEFAULT nextval('public.payback_payback_uuid_seq'::regclass);


--
-- Name: payback_refresh payback_refresh_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh ALTER COLUMN payback_refresh_uuid SET DEFAULT nextval('public.payback_refresh_payback_refresh_uuid_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


--
-- Name: refresh_commitments melt_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments ALTER COLUMN melt_serial_id SET DEFAULT nextval('public.refresh_commitments_melt_serial_id_seq'::regclass);


--
-- Name: refunds refund_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds ALTER COLUMN refund_serial_id SET DEFAULT nextval('public.refunds_refund_serial_id_seq'::regclass);


--
-- Name: reserves_close close_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_close ALTER COLUMN close_uuid SET DEFAULT nextval('public.reserves_close_close_uuid_seq'::regclass);


--
-- Name: reserves_in reserve_in_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in ALTER COLUMN reserve_in_serial_id SET DEFAULT nextval('public.reserves_in_reserve_in_serial_id_seq'::regclass);


--
-- Name: reserves_out reserve_out_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out ALTER COLUMN reserve_out_serial_id SET DEFAULT nextval('public.reserves_out_reserve_out_serial_id_seq'::regclass);


--
-- Name: slaves id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.slaves ALTER COLUMN id SET DEFAULT nextval('public.slaves_id_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: aggregation_tracking; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.aggregation_tracking (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: app_bankaccount; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.app_bankaccount (is_public, debit, account_no, user_id, amount) FROM stdin;
t	f	3	3	TESTKUDOS:0.00
t	f	4	4	TESTKUDOS:0.00
t	f	5	5	TESTKUDOS:0.00
t	f	6	6	TESTKUDOS:0.00
t	f	7	7	TESTKUDOS:0.00
t	f	8	8	TESTKUDOS:10000000.00
t	t	1	1	TESTKUDOS:10000100.00
f	f	9	9	TESTKUDOS:90.00
t	f	2	2	TESTKUDOS:10.00
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.app_banktransaction (id, subject, date, credit_account_id, debit_account_id, amount, cancelled) FROM stdin;
1	Benevolent donation for 'Survey'	2019-08-23 14:17:32.468927+02	8	1	TESTKUDOS:10000000.00	f
2	Joining bonus	2019-08-23 14:17:39.293475+02	9	1	TESTKUDOS:100.00	f
3	PXSAE6E74GXTY47Z9RPGTK4XHBG88QXS0YVPRR4WDYWBSZFY5X8G	2019-08-23 14:17:39.408968+02	2	9	TESTKUDOS:10.00	f
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x44a7420cd0b596e057770c5fe0d017c8986c75911b1bd9795dd09865ddd632ec17213572b46df28e6e46b6fc645880ef6f55dace558f773f8b07781f4907fc86	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f99a47d1c1db3f2f30fc6ecdab86d4eafb6bdc97ed631e469d98f4a1f1fb2197a2020e90d4c9115ddeabb8f370873db71e4f14e9aa89df57fc964d5823ab460	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x025c9bc02f2b5cff41d6b9b9aa864f1429ca98b4e13379bee5c72215eefdf79b8812a253ad8e0fdda75cdd4fd79d3b471084dcd95be8d9a3711e3f79ec580bcc	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ee3ae3e211cc19faa5f931a63886a5b3680c764d82cb85f34d7f32683d4801773a6aa66b1fd25088cea19e2726e2bd5f2998e3e7a95f7d1890b5278796cafe9	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c5e8daaa1cbe15ca5b4616f13b01057de4a3e63c22c2f9492ccabcf8b3a722317d12d122f61c665f2c1050f853696c6db98bcd2fec1af33d29efeb9773773a4	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ffb8005187a2283f0dfc2d95afa178d45ec30395c41255c48e51da4ddef2f179c4b7fa450c538cc5f0889672bd2412aef90cb4575ef954bf96b1d8f3b68314a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x075ae29c2c67d1e651934425c50c187854ea7713a2b4160600b2f10d0c71f0c1a748b18a543456755e769e69e375062841d781170d68f22ed43b569766998fc8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4883e4f6fb69f540054087b52bf58f2296cedeee32fea1d1ba08b803333a42c44b2c1d270757d38e144fc2a940072bc39882b5ca2125ee9e5e007b63a3a05d84	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff818b2a7f0698b63cbaf4c3707f8045f443f7f17dd1198146fc9c597e4be3bdf2c689cbce63873647e23241dedb4238d6f28fc8cf730827c2fab13311a4b71b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x58655639e8b05f6c6816f6d8a175c4590eb096a983ecc0518c888f8db40444aff9982baaff20fa97dd01f80f858d6a9dabfe50beb4cdc0f16af5274d4c3ebd6c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d0f72df2d769fce34bd6362c5eae36145345d5e0adfb141e55c89e235feb589f6a32bda333cf6171bacaf0fc56b13c86891a10dac7a7b0a6569ccb8ae5bf5af	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f98c10621f4f698a1075674d13f00c63de843984d53f55fdfa4b31f25eac9b6f6c27023912350ffe6887c8e6b33950ac9b2dbb943742ce4317e0bdcd6458d5a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd4e6ac5ce25dd68bfb243ab73bddb2aa6e13a99cf9c3fb692205920a110893241588f3ff060362e9cc925616a93c2749996239b5842a9c73488450b32488d65c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9d3672521f6433eed478824b899a2e8eeff183bd87c56035ce9c5ec77ab7828962783fb4303729f6125756e3c2fc93cef65ed5d81786147f6ad24ef6fa2a7e6	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1443b3e41d30c41fdaa5a26e9849903da179443be5094924c97b59b49afdaf4c350d21692bd82090e8efcca3da8d6d2d7603392f00fa210c5e91ed2b7153d700	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5fab009d8c9f72ff3017d0d64ea1fdeda000401d467bb71923f7dc0768b30a4a2b7b9065c93f90be407af9f00c63b6a28bc99d144166055fd9b0fc0a6cb112ab	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3653337daebc17022c89828d7c087f5ec1c70f17b3b85672160469225ba0e28dd79a730d7b2e2424d3784719e2bed1381e3d2406446d244d4e74d495182ea624	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3de3f207dfc099c282b4a15741dc4042f79511ba539d8c9456f0ffe04da56d5f68fa8c8c1bcbf1b9afc15a77be7ae9f68a391ba0b04f067c072fdfa1d0ab85eb	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x553886da8f8e5fa37c3a20067e0f586816e2bf372d578b725ac23f1c3e4aca4e81b784de09eff20f42e1e90ddd7a58439fd07df917fa6aca664582dbc799c1c6	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e1b4211026f091a06d3119d0530cde1b72e8f3f9000b2dcab88681c0b8fc2ce085b8bbece228c016404e6b136893cd8e6575513ed208e8c9ad47f3cf302c6e7	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf74050833ad48ac4cee37c61a3f179090fbb9884d606b9c732cf56fbd47c9f2daa407eab99864d0ea50d4ed30abc372018b56804cb6671322307de298ecff3d8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc00310d950f240ed2deddfeee267d2506e29a433b94721aac27e485b91861aa02872a45203524182d90ddba4f96e12e3d6baef45dd17c56fa09b9776199c8e23	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x62cfcf01bd1bd3d0c2578d99636f7cb3d4bd5478a48114bdca8e8329b19d210433588c3934bf9981cccad2114f455850bbcd0fa552fd68fca414c7ece42583cb	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e8b0c807cba08ae0e60ae0455861cbfbaf6d4e2cbbd54a41950036d2aaaa24efc3bd6c8a239ebde6c086ef106e6a47090eb7f2bd0365f1765235108f3787ca0	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44bdb5603dfe8ef647e906e94332ae48a0d9707d24e56bcde2d677a4d31673c4cccf1718121cfcac54008fef4c1afa20efaa6fa647db0032d3a7b92c90dfdaff	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd8222d3d35c4d6d7ef273d0dbda579a8a0573d59d2e06d63e81f0f60b9b69bbf339d669cd340eb24562fab6260a4865f5fdb175ba9c8d76627aaf05f80c4f92	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbced750c91cf5d01e8cd08584c4c41389d5d1e1e4c3c27655f2dea0345e5f928e00bb4d3f9156a539f86942023fcf50cb65749d58799db1e4fbb3e6908eb0c92	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x25260f6c58f7337390f333847c6c3a7a7a76b6ff1e0c103145580552ffd9f228ae5b3d3221103587f31650da148f391781272f3faaebe4d95c30039f843da5c3	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f731e50571f7bef93883adba9a9fad836a5f067029c75dd4111e591390b2192751aad0816b2316de97d564e75719ddf36fa85c535cedded3a88380a229e9c02	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6c3ef50e6309aee1ef9683e9c5f92b85f9b89ee48c53f8e093c7d52544b7ac0885c0cbc55deba1cbbc8da975dc737cc0488d5d926505fa7666604c60e3814f8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x706ecb39c5d412356710f19c3f1edd6e62d5f3e5a97d496a7a55e6af7a908be4b48cf62cd8387de45c1cd2568f33a46a9a5dc68fbb2e3f8f291ce41f14be2291	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca974e57b25ab5c6d72dedf89b368deb3228d2c6a214b6605c9991df6c9fde25e3daa6239e418d216bf7a69bd4226072e8305d0252b4def342824f2581d9438a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf91e5f330f53b5ba9b2021988b98c8c96277882896b87b4add50a218183028bb9eb1c9a6be0d2b597363979e67620ca949d577b4c011a977a1cedd9d6a11cc4a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf191f6470ce9ab2080a0801f6e53a31385d4626e89eaa1ab2ea6c1eef785ddb01567bcede43411c104844a288f7e18bec14bc75800e39febcdfff1ac33bf2113	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	8	0	0	0	0	0	0	0	0	0
\\x65eab8feb76d4a67b6f9aab5a741c015150dc59966ff1a197b081e9ed618564ece22d05e52cf9fbdfb4dbfb3c0ecda10c15716b30f26d215f539a8581d7b03cf	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	8	0	0	0	0	0	0	0	0	0
\\x21798ada51e7b92f12f7799bd3232ca7b7f6a17fc672a125545dc3c0ecd4aa561731b85336d7c3e1d5455bb189d1a31a9bc70eb0073ece22afec8382cd4a1fcf	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	8	0	0	0	0	0	0	0	0	0
\\x1304e4ae482303f0744d7982dd2ba60700909768952c8582b0fb809f71339f70b3aa34daa656067cb32c6218c302e242065178be9349b4fcf96a6a4eb125f173	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	8	0	0	0	0	0	0	0	0	0
\\x00848043a28916bdebccfd96d8008f8e51c367465789cb2eb9e3ce450b0f9bab19066c53ba0b403f945fc1c1d6df31f0fd7396a757dbfd00bc5d8d5202effc0b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	8	0	0	0	0	0	0	0	0	0
\\xfd3ee283fe2a84be9df974d2663939ca6cc03b8a193246754ff12864754c0f940931fe01b4873193252cd4ca8ee8255175072e66effee6e3bb13ccf0ec1caa8d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	8	0	0	0	0	0	0	0	0	0
\\x14640d6e1958e48995bf4ab6d5a3b032f54a14aacd13f78b44aaf1bfd66d767a643a7cf90d809523475f280fc309efb78b133a221f50cd6fe78b22a01c5c86d1	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	8	0	0	0	0	0	0	0	0	0
\\xeb0e57f7dc6861cfc3cdd71830eba9bb20eb113d55fea71c034981f517aa0b07794f199d3186cb3d9ba38e64a8d8b4f93642be2b2a2978d69193d2afed4f97be	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	8	0	0	0	0	0	0	0	0	0
\\xfc87c057cc8700cc1132a5698a328f5a436d108bb43d65c035730b25016fdfa1ed6a47e6a2333433064741a7e355cef26830df0378b5d3685567209c1b5e7e9e	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	8	0	0	0	0	0	0	0	0	0
\\x84d7952128dd1239e3d55e725ab25d21cc9b62a2b5d300c7a66af18a84d6b2a0e2b12d5e7933f6f6036951f1503221f9b4dcbb118936004e12b5da8a568a169b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	8	0	0	0	0	0	0	0	0	0
\\x3e1391c0ab1be97860e77300f11bca704e507219f40eda75993730110cb619f83e51208d81a89c8023de2bd041c1a39823c2e5fd0b01753fa6d17c1f102a3222	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	8	0	0	0	0	0	0	0	0	0
\\x858e17abfc5c00e4b3da4d916337f47a5ed699e4068ec24aaab67cc6817a8bf95781f5282736dc6190df65701e74fa040cb7fc037fdf5ed77fc4f44556c95b73	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	8	0	0	0	0	0	0	0	0	0
\\x1cafdad5b8bba80afd47fc7bbecd16b3705970628f925003a22639988a589296358b8cbe61dcc9e5888646f583027f0aafc498bbba527bb81968292203b79eb6	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	8	0	0	0	0	0	0	0	0	0
\\x0665e1d85263be2570b9af10a24293c514b2b46d25a0029e51047a5c953ea8b29a23648db28b31001251448faf5496680c5e628d10230643c54c7b9baaeab1fc	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	8	0	0	0	0	0	0	0	0	0
\\x5e9644e5f5d68a67aafc54196353500da69e2a37be9752e41e33bc4dbe6dce34872bb1f00011c07597d1705af44f1eb132f36010ea8ea2b3ce820db98ec4935a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	8	0	0	0	0	0	0	0	0	0
\\xd80a2b5e01bfa6bf0613ab6f5ad490613f40c7fb2bd1c2f8ff73c07c1da54b1f16f544863c7b488dee4042ff2fe38eaf107a6c97babccf850910cbe3331f0837	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	8	0	0	0	0	0	0	0	0	0
\\xb0d1e16479fa8de48b860b351ae6d7e9e6291174a8c83099520aa4613b9372b0b408bb3bd4b79d0ad68fe30c23b463c03b0b4894a54f4a623bd1d65d6bc7e5b7	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	8	0	0	0	0	0	0	0	0	0
\\x1c4f546efda708fc21cb77763a15a1f05b86441486c7cf791a6628d14083c8dd142aa4074be70162c3ede74c835f1c7c2c6d07dbe2b6ea4b981e8764f224b5f4	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	8	0	0	0	0	0	0	0	0	0
\\xcf025368e159d0d844e54d5961bb4ed56abb3b9901761520234f7830f87baf5baa6432de1a55f71007916ec209b6d1c840f82d1da303dddb85bb0795e8138f6c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	8	0	0	0	0	0	0	0	0	0
\\x944ed094888d9e71882a0186c710f15831e548a432357e457a855e5452affe1cc09ab37232347ab4e84f18cdbf8b48007585a08d1993a18d84712be576d4b019	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	8	0	0	0	0	0	0	0	0	0
\\xde63ab33a9bfe723c22ab295d1ac7771b0c20f1b061f3e2d57e4def6a4f94f71fda539c9f5e4c5650e22113649f211ef0f5970a6520d6c93d3e35a93921f161c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	8	0	0	0	0	0	0	0	0	0
\\x2cf0f3cb9bd0e77706a230497e424e7c45f270df6de44f00cb0ad675043478e3b0e2637a83f584609f5ddab483003c045ce0387ae4f47401fa89ba2c7e044673	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	8	0	0	0	0	0	0	0	0	0
\\x1adf741160da54ef145fc1bf485d1c28008213c3fdad505a5c2ce72215772d05dea2ea41082604f6e1ccd4f09b400e0a307668045e22a21d8641d266c5049b55	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	8	0	0	0	0	0	0	0	0	0
\\x33bf2424afc07c9a9bb96bef018ccc9c398bbfabf296697a6b4c6ee2a9244ee823009d94340762948482b8cf7311d5bf098826f87db77da33fe93086f72d5a29	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	8	0	0	0	0	0	0	0	0	0
\\x0f80e3e6093a1029419e2e26ac23009c84601adbc86f7a37295177864760a3566e1febd08cbd07893e6f98d75b17f8a326af0c79ac38c470458470abd3424b88	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	8	0	0	0	0	0	0	0	0	0
\\xae3e8755df29b12365ceb6adf6b282f0f83fe3f542990e25d69504bcd711c5302d7d5dc13fb48c363e982436fefa5748a2553675acb99aaf87588931f71b6d24	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	8	0	0	0	0	0	0	0	0	0
\\x554041f8abf6bbf5abba9afa4d71f364c86b543dabd6dc07b555ce490894bdc5f3cb1ba6cf44e2e0d41dee813c565ea4f9477ac2c6dc3c500fb025bc4d04b058	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	8	0	0	0	0	0	0	0	0	0
\\x2829d084beef4dde16649a13c6b9d03abd75a7c58303eb05a85cc928d58477b22012d09273db64ca8a6be7df20d6f302c895a0331688d35ae01cdfb461a768ba	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	8	0	0	0	0	0	0	0	0	0
\\x6cd5bd8837be2d33020913a45cc58eb6b66b0ce681032662df2be4221d243b7570eda0786635b9f63b9ef0d31b03a76b7cec7be589ab2af390c149509e8ef501	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	8	0	0	0	0	0	0	0	0	0
\\x3d9725fd3a4611bcd23846500f14d6749991730260c3f2bf865775e0f6aabfa8759baacb00e56244ee8ad43d2724982b991bf14666e28607fa205c5bfd0c279a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	8	0	0	0	0	0	0	0	0	0
\\x0380f74ade720aa5cea0c041e4c9982a0f1814d48e4eee8c345cb3f421d671537b6396a8541efc9cb94bcf9eb94245081970006af65396e0cfead2b634b05e19	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	8	0	0	0	0	0	0	0	0	0
\\x70a77f7e51e172df8f02cd16e0cb3ac5dc6c826b688afac3b82134a6b4c8ae204a0c47a0e4aed2dbc9dfd50f8222abe3a35d087bf8e19a8b5b6357ae3475f7e0	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	8	0	0	0	0	0	0	0	0	0
\\x57f66400183fa7a125f5d68de511ea0a12a4698004e3b1ad0f7e918c6a0b8b952e575201fddb09da6f235fed21aaccf0b59b460e97638a83ebb859271747460d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	8	0	0	0	0	0	0	0	0	0
\\x45ab235f322f4d6cb801e27e5e5ff3c39fafabc5447df36dae59b14b4276214d10b8c2a0c40b3cbb87e38a9b1d1ac78285f96781e243d65a0e6044f7c7601f0f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcf5bf5f62b051b8b8434abfd397a12cabbe1dc4d77e00d57982834267729d080facd7d6b687059982ac59379abcbcf1a7eb7a92b07a6e708e96f40edb0ef85c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2004c40d9d41dbdfc3778647894a836c4a914ad12c08405671d8a1eb7620f899bb1e75b1b3026f11657b2aff47985803923495cebc07e1bf90bd9708150ff331	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5bc7a2be153f02d623157755310d5f5578cef9c1f700d69d7012c78e6236bfc1f19bf2a112557145c4c29ffcb59325a0c0bd64ce2ce692950110e11356516ab	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17496f47056dfb3bc9d1d216f2b19ebc9ce0428d114018ebf43c2a2f4bf7a4631b701b6eb18cc6fd471955c9475085dde983a28441b58a52a15ec5f505f34b66	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x565a02d642d32065eb665c5d38f880b72b1b43fc406b6a8e909d54eb8d1eda62d72816f9bf9dc2532396c650dbf3bb0d9afd0ae8e9bf4c00d91732f257c70ffe	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50b282ac0b9a29872b64ad05ba712c724a0e1fb9cdbb689d172da9090e5764fe116dd26900cdc019ce470d8e394f2fcc9a29100f44c30c28acf52a1302bb2633	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0587c362ed090ed7bdaec431ec88548990f0a69a1d8dfa006ad0373c874fc020b29e2841b181aaf5779cb8e74bb0d766fa1a179a198ee39f160049b950a10701	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1feb672cb2d1dc5fb80ff00c7650d8ebcce9ff654a5e96963fbfdc9bceeca34afa35b08293f3b70252132dcac4cf273d2efece04dbaa8e2a48945944c0ade323	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x81cdbe33cdfb0f30a7291d96df4a3fdb4bf696627eae7f9ce246ed77ce67cab6b902ac04625acbe931a4410b2acae8ea370e709777e2f1c135fc953c5972e47c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x10a5d8f38d6761e701c3b2c3bb507aeedbfa2cf9f2ea130ceb79560616edd4b10661446cbf0e35ee172278d524d429f319d2d94d3657e7a887b5554f89b69db1	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x85d2a6c3d907343508527be31cd057987c60cfc7f90daa921b43d28c44954c9a3c878f7ad6d98e4a75903c17705d1c4972e34b0e3f2b981ad84e19569dfa9c7c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8df1fb679c72f7a37bd1e521241a523151f8ecc54de80c0080586c15f365ff30c673ae55013bb48f4e8cb8a321473e5554f375091e0e3fa1099a24d2bf6eb794	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbdc37efb93fbe9f870cf31a8462592651ba90e07e4347ec7a9c3bc8bd98d9c095670445b9f1d757aee239ac3b0a3d1ddff01e4456352648f60a0880df9ca033a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb007cc706e59ee6298f2e6d6c96f276cb07f0f82485b88afe174148336a4c802f13f03615ab83b976c73853d202d1d0bb3528befe2afeebdd31a02682ad23b27	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x280d4a0aad4a07e496f877d4034eb244bcbd219a10aa24c6c8f85ed2e14bd76e1b2a3ac5119a716c8e06f9387e6ffa6f6278ce5a5f6d87523c9a0a5262679430	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4736b4b661ea1675f624d03df2ee4088b0389b1bba31d19fc794a6d8d811fe89ba6dbfbee5622772fceeb56a41a61f719203cfa60543bd0fdf428285c1ee1005	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff55ce7ec1fa03c72d2bd12a4dc16ecde824672edb3208e96dd475117374eae74e0a033d012f81e0946671aa0988c1efdfab2bbbbace85ab32dce0f56bc602c1	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0711be223906eb2772db53ea9012d614d5355be5a56884ee815ba5edc138fda63c37953bc5627fbdfe134a10acac5523f843ec1c4d5ee49b9025c857f8f38f86	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb19a5c2f74f4db3191998efba3f35a1c05766b486d0892c5d5f70146f0a3164690fa4e6306468f9ea349f09a445294f92d687182302cca7cf2e0d30c611758e6	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ea6e23c401c04568a39ab43c3dabf638c19ff0531156f134a89e6169516e80127b68ab1162bd110c68c35db0fdf5ab79be77c69bfaeb64ee112dc6d12b46daa	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f8a8a440b11834a5e9444c6b35977f4478dfd1e29609f9113581487bac331f2ace1c7c3bf44a5ff0cdf5c4e5ed100e3b75d45d30529818c0bc5ad68aba42a4d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a596ec338f484242383c6f48eb89284714f4ccc40d835dd7b4a773eb2db309350e6e5b484f671cd52d7cd17a88828a6afa2f32c0bc77c317bd9ba6bcb77d693	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa750ae24efdb5bb2e3883cdc246a0a52587e4d68773884349eaf855ac80d1b71d068abce3ab63e0abc834af8d442598ef024f6e578bd8eed52a85c21045859d8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb1bedbbd1f6c03c488336fb3b25f2bab5f5b08bc50b7fe29a52a5601f93df82982c6b9f5112596ef68bb896c0feff10863b2bfa3050adc6b5cc89b49e1c2217d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bdad2979b4847aa4866d37f7678796a63e4e54124c190fd9bdc59dd4f932810dad35d6b5e335bc376ca1317dbf014e346e76d2367ecdbbd02faac185f1d26d6	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x96dad07e373f4eefaba6c7aec596285d7a707db1a2c662ddb796b18512042c86533bcd1957933b41c20ac1ef45b92077482a97add2269b390ea49546c995d354	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8e28b182a660cad862b0edd7b702d9f0cecadaff8ba038b083ddeb8c6b20fb72ab3505f0cb35dfa710e78916a180305f455cd2cf5869819d815cde8b3857ad0	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d33d2fc49aba87996bc030154dab03ff780f59583d3ad9f7369f5373b74874217fece9650077e6c56385b2a1addd4e7d65bb00e892d1d5014cd6f2fbd6d14cf	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe93b48185d9923726a770a0ffa4f9b0839edd2740022844507390cf5b5dfabd66a015985eca17cae5dc9361817be2bdb2bd4405301369ce3851c1164968481a2	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1832b5d68c16478e20f3ba292658c3545de508e8a1d164191fbe0c66a8892c243845ece80c5c264c0f04426a30d57e102b37f84ce53d64ba6c51a1b502095d9	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6cc5f5d46a7308bd777e3e78b8ebaf3ab840817755bb6238e0a761f282ab8f05856e2eb703eaafee980b8474b0b31becf40a78861af517d268a571c971f28fd8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x067c9a92af2db1298cb3bebdd68bc664516db6b9501dfe4f08120909c404e42f06de8316cee37b80a8b2d15a99b3927083ed68e6fd2ef57d396379d37a5a7b4e	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x26269c80a6adedb06a7aa8505cd4ea51e24c9cd45fd93f2cbec6d75992fdfcc2f92ecb255daf08b59361adad27789cc32cf5e028443a75e11050d876a4d8791b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	4	0	0	0	0	0	0	0	0	0
\\xa511bf15b6e0744bc46344cdba28f9acfbc201a7b11a781240d0dd34b619b73949da62477e8f04b7495bdd3108e096496ded8ad93dddbfa669d32c6889ce1200	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	4	0	0	0	0	0	0	0	0	0
\\xeb724b4b733105f43674463f8ea6475c45acf3772e145c56eb760fb2027edf517f8e8ab89948106a15ed27f27c81e34187eee4438f80350543fc62258a8b5dca	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	4	0	0	0	0	0	0	0	0	0
\\xc4aec9fc286def17164c6ff99ededd2433b75e9a83bc44cb0cd172f271d9ccbf71b1a612b555b74cdea4f24d8e7be90f5b3ca5f485f62c88fe25857f8f67c4db	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	4	0	0	0	0	0	0	0	0	0
\\xd8add003543f060b5ee3ee26262d6208f96a8bfd3f52ae53e502377083b696e7ab12f1b791c0df1dc5452dbb55aab2fd1c45d05fccd1714af3a3a7e7bb98a402	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	4	0	0	0	0	0	0	0	0	0
\\x6b1274d91951615a68b9280721899c7ddf7cf4667509f36061d117ab3287cc4eee10baea5becca5607ba894d064d542c1412b71389b282591952eeccd6fe98df	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	4	0	0	0	0	0	0	0	0	0
\\x965c89e6ba1e12ab9252d9dd5c89353ba401ec110586c24e91f10ba466bf15cd44b4fe39e21a87d7837faef51ee44da0a351544d7fcf70cb7cd45638f12126cf	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	4	0	0	0	0	0	0	0	0	0
\\x7f19d7f3c340332a582c9f5acb404f860ef05e9b2583a098b952b21ce2bf195b99f69511ba359a208a2d5664fdddd09fb81b76fd0dfe9bfeea91dd74b756f9e7	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	4	0	0	0	0	0	0	0	0	0
\\x27f82449a8f3727a99bb6f913734bc82da49a4607343b2ef7e72b0ce0c3d1125f9c4b1e4f66638bcbc0d5f16f565087f39b5708f08bf087ed23556add20219a3	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	4	0	0	0	0	0	0	0	0	0
\\x7df93b145fd9aa4b5e19f21e892c12ea19d65d1cb2a65617c8a0ef0524b74a59ff9cdcda131fdc3684aa267954d2dfd2971b441aadae343cdf13220af0c39b16	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	4	0	0	0	0	0	0	0	0	0
\\xdace3c2067c42069a5c19e699eeae31a57c44e3013e8b4015b801c6b92d24f6e9fd384859714c9488e4af314dfcb0489ee56755d689a94e49d14dc127fc517a5	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	4	0	0	0	0	0	0	0	0	0
\\xb3dce405c8bfcc0623c853c0e03395e61851c63785aeef9457eea509acf5b2f75f3af029ee4a942e36633d7a5d23e725d5bcb9e7097d4efc14f50b9b97c15277	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	4	0	0	0	0	0	0	0	0	0
\\xdf83e6d9da1f27230a915ffe89ad7b3dcd54a80cf51777f4eaa2c6604884cd5bcd1d6c55c0e297e41de641c83a19d9797f3aa892e35702864e0fca193860609e	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	4	0	0	0	0	0	0	0	0	0
\\xfbc48ceab9dd40fee2c12991325b9502d79f32d05cb2516ba8d01f6732d18d22316084400d4355cf9b5ecf7b91012bb9e42c8cead72e900531de070cfb61905c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	4	0	0	0	0	0	0	0	0	0
\\x7bac66d164a66ea93306f1c2e50b7a4978352cedd5fa314030c3ba9b7c9609be6759ae620a9c4d7430191937378fce5510c0086ad98d63a1cef725bca8ce6d8f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	4	0	0	0	0	0	0	0	0	0
\\x6e17c72fa22b5185bcb5fc3bb81c0f6016dfb427c53c01ba872c4df3e86278c9f5ad932f276a9529b4de1a1db63ed8a285b5ee1ba4f71d9381928d3ca11bce8b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	4	0	0	0	0	0	0	0	0	0
\\xf4964c34b2278b2da0a8538f237bfd0f5d9c43fb58859f0dc46d5cd0fe4bf49fe17a1a9435b1cacdd80002d711ec9485e30dcdd8d2211f6c0960b035c3b2611d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	4	0	0	0	0	0	0	0	0	0
\\x3466f262ade16564e78ce3245272a782c95e5886bfb5cc833822437661662053c158a8839476cbbcba28ba781a1c2a5b0d12cd0318c2946ac4a0028c5215c75c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	4	0	0	0	0	0	0	0	0	0
\\x97ac39c150d15a7c4b9600395104017af56c510fc935d43679d2c8f111bdb3e613816dffec008165e3d03afccc8adbe29ffe7f6e83fc74e08a34e84586fb872d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	4	0	0	0	0	0	0	0	0	0
\\x3f04ee6af9724c9b9c7392ca810fe1269f9664df1978ab1a7fe5b091ec5f21a32d3b29bb1cd51d525156789950f72f3587e292b07044124c05bfa96e964a9391	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	4	0	0	0	0	0	0	0	0	0
\\xb61d2522a71a89b2133f31971d9b9caf62ed36f7e38f467f7ba7e91d1474f6b33d852fa7efe2493e80d726079cb4c13686ffc3f1eff661a4d0d0880f073617eb	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	4	0	0	0	0	0	0	0	0	0
\\x6afdae5846a037c3e2c3681e024b6e401ded342dfeb3de331835351288bed13bc5aac55046c54bd9bfbca8044ab3027ff236a04d17dd615fa61c4a77d354e252	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	4	0	0	0	0	0	0	0	0	0
\\xa9003af4ecad11a347965676d21aaf80cff0ba6c01f1a1bb943e780e1994a708db4fb27879d0ae5a7a235a69fea79473f5c7f9ff3d35fd11a901d6a73ec67c2d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	4	0	0	0	0	0	0	0	0	0
\\x2a88a9d6210f2610712879054db67873cb522d1c266e7200f56de7cd48d4ff8704b41f9742ea6fba6f9db477a9e07dda24880429270ec8bc2c46dbcb343b2987	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	4	0	0	0	0	0	0	0	0	0
\\xb9040b70275172637caf6a0daabd432706391187bdcf86e4b4ccb4afafbbdfaeb985c76ee182f66f987522a18f05c8acfc9733d01a8aae1707125ad3eb092b46	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	4	0	0	0	0	0	0	0	0	0
\\xf0a17737adc2a5a43b7627b805556ee179e02a8fc35a737d6dcaadff0b853058c8b98dade409d776d33e07d43274f9bc2371ce15ac3682c4aa70c7866144dcb8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	4	0	0	0	0	0	0	0	0	0
\\xee7a5ba1a098709bd985f3a2cb882f754d741e839d24948ba250b18b1e6d2b9de5da3d983b3d1d631186c99400e0205a7dc78aace9177f7ae738db759e923e42	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	4	0	0	0	0	0	0	0	0	0
\\x2d8f7b09dc05d442a715ff5c6398644d7dcd574c18f6e1aaf5885aad0deea3da57b4880b2baad5f287e14c0740dbfcd60fbbc8b48ad9d323d7090447af795e77	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	4	0	0	0	0	0	0	0	0	0
\\xe08f748ebe7f822628f77921f3383365aa0abc59b76cae0c1bf581e81e316d6a604cbe93eeaa8df379dc24d63528a21c6385cd6cb657f089ef5c800bad3e5516	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	4	0	0	0	0	0	0	0	0	0
\\x5fee49a00346058f8aa71de63155232a80943844bfefcb20b806d14256aa48ed6acdc1621f7f498fa0056162250f947c137c9c7f861591dd786315f49b159163	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	4	0	0	0	0	0	0	0	0	0
\\x2a2f37150e6dba2c36c522fc98ff30fc7b6a6c6bcf26719c55f72d09da0fd2c634a139d7d844504d0cae505fff5a291506d04121361202e0e6fea6ee54115e50	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	4	0	0	0	0	0	0	0	0	0
\\xd0465befe3d2e7c3805f580c606f692385e359e512e37843b326b520491dfe5e4f6d7c8f3e91ddb448f95741967682e73d59da2dc6fd6eb679c4a3e9e5cd6f73	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	4	0	0	0	0	0	0	0	0	0
\\x59c56a38efba217c4606190b6e5051aa93e962bd8dfccad7e10f137e8c8846580797bede742cee745d7edb9a409d7c6c3a3e61f6b5d534506f5b28e97cf8374b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	4	0	0	0	0	0	0	0	0	0
\\x9e1af932e98982d1941c48ec4e1326a3bf4b7e68a35e6e266a2ed60ad51977e8e5f98ffa275503f73c5647e51c46493a7a31f140e93416416cd503ae64692ef5	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	2	0	0	0	0	0	0	0	0	0
\\x6e17d8f92c158e2afac32f9354d5c3fe1401557601e4ba0a3d5c7e282e7d17ac66d4ef9405c9e4ca1d67f66e4454a67cb88ba9fc6a2b8f0b51c5ed5f87a12dba	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	2	0	0	0	0	0	0	0	0	0
\\x15be992d006b1e2ffe99c5e93014c71e36469566df02cc2eb5c3d28609d014da255d28d2b2644997514359bf79c32cb9782710952a4316d12a187eceab65cb25	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	2	0	0	0	0	0	0	0	0	0
\\xaa495703aec79efdc93d9c482c378834c28eff1feb5def47c3c316ace21c8b10e522172a030937081d3bcb8987824f37ab7e5e7416e6089ef60ea3bebc27e12c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	2	0	0	0	0	0	0	0	0	0
\\xdb15fafb8cf70c947a18ff4cdb9f01cde8a21adc2cd58bea8cc8a346f757363da21185d9dbea1621a206f3e21e091271e407f0160b52538ed9ba7244ae4a326c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	2	0	0	0	0	0	0	0	0	0
\\xcf5d5d6621b4a36b73cee1ab6d038e115077ddc31785ffb1db85664da2d7adfb308da703a7b858a15aa903605160a7702882f778da6f0833ed0398db99bd3ff5	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	2	0	0	0	0	0	0	0	0	0
\\xe02bdf832b1e19b4acee03f3c98d7af7f01160e880ac03f92bf6b579475e3d3ffc8f9f5d24d3bb57afb9e44931f72569c6ee63944a169e551a1e6ad6841c09ad	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	2	0	0	0	0	0	0	0	0	0
\\x32f8fe7f03b034660f74ac14558a8fdadf38136e91919db0af38bde74ef1b074fb23e3040a3edc283189bd8a22c7b69e29e291ba8d0c30cf5856d928b4028fd1	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	2	0	0	0	0	0	0	0	0	0
\\x648e45bafc000461598b238a25a4d79b02c77353c96166b2c7162546cd8d5634f403e1d3fcff825aa3a85333c4170637579ce2a7827af1a43bcab311dd5cf106	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	2	0	0	0	0	0	0	0	0	0
\\x93c3cfcbcef26eed137135a22f0dcfb41b3601927259154122378d23353962869c680dd8859abdb7203fcc28941ddeeb26720d196c1cae12eb11558af33902e6	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	2	0	0	0	0	0	0	0	0	0
\\x366210f9dc466af250d9c49904f1b9073df9a34c0b918c0d825ab29d32ee00a04867dd85e4c65f0c395b9e54b30f99ab225bc20d73acbdea4a472dde8f35ddb4	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	2	0	0	0	0	0	0	0	0	0
\\x7c4c7e6ee06ed69cfc836fae437fa81b9749efb7f8048d2126a627c2f17fdbbbee020c8ef55c14f016bdb34b4edb63af68bad6ea4da05e24f980f2245d2829c2	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	2	0	0	0	0	0	0	0	0	0
\\xfdf8195a65905a5f495074260cfd7b02953ae4de56359ab8d006553806160d0bb85efb80ccc15e51a6ced3715ced813ccc98c6c8710a24a948be28b8050998e9	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	2	0	0	0	0	0	0	0	0	0
\\x8dcc1e85815f2be810879ff5847973d3fc6614b78a3b2ee9e54f71bc1d580cd9b19f79557e6ad4a5e81f469b8a35e3b18c3da5d53bd6ce24101deec8facbdcaa	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	2	0	0	0	0	0	0	0	0	0
\\x16f0d106c29c88b94439dd5ce9f039e9f37921e5a3d2b812826d0a6823d82bf56bc885195bebd79583e284cb336913cefcf39c3507792208be0b295c3eb3f63b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	2	0	0	0	0	0	0	0	0	0
\\x2c1c217c1cc61fceea1f205013072458414fdcb433ff034b2bdb1a632fb591495e6c001eacf27432281d1153eef5f8c6404ac8ad8a58e69b734837136058f0dc	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	2	0	0	0	0	0	0	0	0	0
\\x7be88b16f33f59fe6e5b1665dec628dc953733a42481cdb4698ad76d9186c96a5d067d859abd02e67f21b16d5f84e4ffebd8d675aad940e7df3435c7d284d959	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	2	0	0	0	0	0	0	0	0	0
\\xc26e0c34598e84d3fdc5643d8f2c0ea909f85f0e97b814f4895703de5d1e64bf23d27310f7dd675741c61a924b131eeb88d8e2e00f447a5950158dd9e53ffc5f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	2	0	0	0	0	0	0	0	0	0
\\x9fde9ec29f6ba31c26c5a33f12986f6541caf3f505215740d1280e70f37523b7059abecbf5cc43db28d3c1143891fdf795e0f2e3996f3c77e31a992524de0ce3	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	2	0	0	0	0	0	0	0	0	0
\\xcb995f6afd20554a672e048e0b4cbba67adb0d8d667a67c9a55d4c0a85c052dc1784565200f61d8653b9e6b8aeaa7e08ff896cefa2b156266f4c8f8a24baf97c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	2	0	0	0	0	0	0	0	0	0
\\x77c193ebf86048e7a0668f2aa70ef91afff356f477734d2bd5f9ae12615f9732d3281e1f98627f373a7e809afaadcf05b8b88d77fb4cb2ab11e25858b6fd448d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	2	0	0	0	0	0	0	0	0	0
\\xd37099c346a5be2035f5886a42be7f36382b56087920bdc5738424b7b04a08f091287ec2b04a7e9ef458094470a0be21e0b71b0db54764413988ac2a20c185b3	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	2	0	0	0	0	0	0	0	0	0
\\x9e136d18395efc2917f86a5af37c6564866e813c589af0d9ec8753f59fbefa0d0e81c86da54e1f7d5709945a530df10eb5831fec3991bed5e85b7437fdcdd18d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	2	0	0	0	0	0	0	0	0	0
\\x1442bc29e40607628ab4e993317cf7f2326757f1da15775c83355299f40459f8aa35f2acb9d24ba3342da79d1d4fef8aafbc8e00858d5b3795404e9249c8ab76	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	2	0	0	0	0	0	0	0	0	0
\\xb68415f4cca447b52c31b2d9ad25e9121a2c2e54a7dcc1325eb70d60cb2f336ab825c896a53cdecc1b1bd8f76b05ada6b7d678742926d9f6719ab33e592d0daa	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	2	0	0	0	0	0	0	0	0	0
\\xe34779e791789955470f5d6765110c34aea3fe80012b6d712a4f5187dc08d2e589b6120d1d443363cc8a7b69332f8d8c77420623e370448e441d618421208397	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	2	0	0	0	0	0	0	0	0	0
\\xaa51ef65ea80a72e59420aed5cabc57126eb620bcdf26db0b62c70e2fda26ff41233bb6300b907950d4957263879aae0f6c571c5e2208a63b30f77bcf5ec12ed	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	2	0	0	0	0	0	0	0	0	0
\\x55bfc3947d7a190625e150e673009ce1d4d7d12e9e960bde10e5064427d70273e7409c33bbb64cdce4ee0f3009dc8f60649d53b512da65669729b04d7a3994b6	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	2	0	0	0	0	0	0	0	0	0
\\xaac58021a98bcd5e97b7c7c4172e241197a1ab44c9d724fb401f8953382c0ccaab4727f1f2a5332aa96d2c28a6c049321fd017f02d7367e903793bea1e99e2f8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	2	0	0	0	0	0	0	0	0	0
\\x5bb5b4d8963c1b2fb952adf53124c65647e17eeb0f381fa836dab06c374ed614424474d152e53df4273f5e6d145dabd299453913657c510319ab9c5c624c5bfc	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	2	0	0	0	0	0	0	0	0	0
\\x5b4c2506b566d17e9140676035b2939d453419187a8949c8275e984b1e9a0fcd6c7d12aa7b09802e85afe039d137f8b06392aaa156c06b8e9737872fe151a212	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	2	0	0	0	0	0	0	0	0	0
\\xdc2ed8bce8ee2b022e5c6ba955046f76ce27600bb644f42c9e56cc1032662603fe5579faee217bff3320ba5218f8178a7ed4c35965d58ffa8144aa2f6d3396c1	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	2	0	0	0	0	0	0	0	0	0
\\xfc9dca1d0f0d07a46c78ca5183288bdd7d05ed913735f1bb4c196a96e2ac6aa18ac899b0c2365bb64e3e219ff66dbc344cafc87207eae690862de62ccc382835	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	2	0	0	0	0	0	0	0	0	0
\\xd36bc87543208f087bf1fa76c3e82dc5755897ea0c67167a4c4538a6e4830b2b03d9b28a107ca5ce6e712750865fa9b375987121543b068f9899a5675a052b3f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	1	0	0	0	0	0	0	0	0	0
\\x5592a06badf9e47ddd995c2c4a5521ca864242baab2168762e6a3366f7c43aa470f15495931aaaf8fa6f4425a6ab66b5033f8c8d358de1707f0aadb26790d9b1	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	1	0	0	0	0	0	0	0	0	0
\\x1d982dead6b50869aae976a27af12d17e409e4292473bac6f3a041a6d481595fe185c8f0903c0371217bd5236995e13314e42716c1079ca941d43b04c7dc044a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	1	0	0	0	0	0	0	0	0	0
\\x7e5b2e6babb6752f44cfd139a7516343efba509add6010fec9007989467cb7d157bc65ab25dec9605650569dea927a9c64d444f7706ed82dd654bac96ea65e6c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	1	0	0	0	0	0	0	0	0	0
\\x38e73dea344464944b1ea20b426e561d6dc57cef3144e2e7f56a9e5738efa1a9cf7da7ba9f351fc41b141bb046f9647b47b5f95383c7bd2900cdaeef81ddd20a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	1	0	0	0	0	0	0	0	0	0
\\x67906d292b9102c837928a5b21759b1dcb1c644f0cf746bcb5d1b40c400f84b1bdc0a3d402be973a1db9c76cbdfbbc7e70f42f2450b9e55a3ff103a4e7fbb64d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	1	0	0	0	0	0	0	0	0	0
\\xc7379b28357f38a4840fe4a2d21b2d7014536f624426a0e46ca0dc9cb3e7e50aa9a8b5050437b6d4ad66cb6519cea5443c7607cc2ed4f58a68e3e3227455548f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	1	0	0	0	0	0	0	0	0	0
\\xe9e99c6e5172b45ac006e7cd387e7575409dd9908870bf1ee7336b1e2d465a05796ce52551fad8ace5d1c8ab0bf84b458f844fd92ea668b6c904b55c7d4bb389	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	1	0	0	0	0	0	0	0	0	0
\\xc4dc663d5841d431b9033866c178c619790b588aab9201e6b844e1c1f20caed3456784810ec03ca0aa66bbc0c0377e406ff168c34e7baccb823c166d285a9e1e	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	1	0	0	0	0	0	0	0	0	0
\\x8322a65f8273e093b47566b6f04d58e2dc16b52fc76bfa276433d038e47668277ed14246c12312e7adb96c6717e6d8d4efc2e1ef76739a2103d6aa00130ed38b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	1	0	0	0	0	0	0	0	0	0
\\xf7672ed493e26bea23fc02968b7fd6acc0bbddd1c7de44ff7a8c4d33b565fc138444648922740cae89c624295a6c37158a10145bf2c7c02b5d317d38ed7130b9	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	1	0	0	0	0	0	0	0	0	0
\\x32cba5ac822f77b2a8b9dcff2804d7e82f8d29261d4ec6fbe12183dc21eef7e63ef4f2c1dc353bb7d12c76f2a6cea0857e239abd67015cebb5e6abcf7938f90f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	1	0	0	0	0	0	0	0	0	0
\\x6f9c86348c3473c4aa3fcd157ea31670373894a76741bac566d625cb239582e5834460d3d0eb33f753edfa84584988a3acd5c14f47d9e98ba4476d498292fadc	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	1	0	0	0	0	0	0	0	0	0
\\xf0946d6cdd1a249006783c012df6251db617d98330ca2376947e88523f5dd3b4eeb0ce34077e2e2c41c792873a5e6253431fe14e73d3d70c5e67695e7e7a6297	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	1	0	0	0	0	0	0	0	0	0
\\x8cdb67eda03cdf37b1919cebaf694ef567832916d73ebbe4c12c6080f0169edd2b170476b909ee90dc8a78efd2db8e8af92d2e835c3c1e07fa1780f13bdc6621	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	1	0	0	0	0	0	0	0	0	0
\\x574493f6d34caf1408da7d620c850367e632da5d9f3f6a57a00ee0544fb4f8b618744d6501308dc1c55095e103cb82fe2b6078562f25989a0044ba7c89c57902	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	1	0	0	0	0	0	0	0	0	0
\\x37fb1bb7d0d7f0c278294e9db9bda5976c012c71f5afcd6646b09d553b6f51f6d4da0e032e26934d64b1f7d2adf1e55402da9fb3c7d6cc26a28d9f744bdf99ab	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	1	0	0	0	0	0	0	0	0	0
\\x24132d3ff97af545d2e5d0adabf50dd1936e3fe55793a8293f6daccd30a2135187d9b59276375a45094207aa608a4b6dfe30014ceb3cba3e5d41fe2f61a0828c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	1	0	0	0	0	0	0	0	0	0
\\x5535dfae0a92aa8468cb43de31cc842a47d92115e6a0d4cb478ace259affe21668f08b992f663b177562e506d7f727d45ad410731751152c8a9070e0599b72ad	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	1	0	0	0	0	0	0	0	0	0
\\x12d56a1d16be63bd5975d117b40005e5e0c28a9dfeebe63c88967ac22256f46dea0e2f64c214824606049c1d96db558fe88c829961f9085f5d97852b0757ab8a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	1	0	0	0	0	0	0	0	0	0
\\xaa2d08dd7f38cd5d1ada9d8631f917c56a3b6dcc60e02a3440ecd2f126ff93058d3f7471a7749538f56c966225d6963346a76ac099f782b2538d5ee76af58e29	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	1	0	0	0	0	0	0	0	0	0
\\x54183aa5c86c5abfebc0188a9f12e1d7402118936b677cc176f4cf90347c59465493bebc9c0578c27fb862ceead032e5b340ce5afb5c089a8a68749ce94718f8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	1	0	0	0	0	0	0	0	0	0
\\x0f3ae3d7601dd0e1609165a749d6987b01e3b833200cbaa839f4d0aa72a3fe5ade519ba466235dc0bee376bb41b5e84b9ec9e01846c61f308401c4f734ff380b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	1	0	0	0	0	0	0	0	0	0
\\xfe4db273faf619d1806eb9a4afdfca3a3af92e078c7913f4036dbe57b9a16d45a13d6de36a99f7bcf58dbfcb0386a83a6cdb6c4f00ff88e232d0518a38c7084a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	1	0	0	0	0	0	0	0	0	0
\\x60af3a2c8dddb98054db2204092d6c81dab75ad81bbfbaa04b6128a47724f720292fe76d62b32b936ac419934825b6909d97187e80718e2077c4ea7fb8f8cb15	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	1	0	0	0	0	0	0	0	0	0
\\x835947860998b625ef754a9c7d16d5f8aca6df756f19ae050dcf2df7bcb51a93e8e70c529c3e39ecef1dc7e13c573060ea3c24c0120c4f77e26c7ce7a6eb7dba	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	1	0	0	0	0	0	0	0	0	0
\\x045f2cf60094a774ac0ea04d12f4c664b2e234fba34d436b75f8eb1b5780aeee655f07fbb9da4f11beb549176273fed40692ef58270cfb99faf488b4441fcc6f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	1	0	0	0	0	0	0	0	0	0
\\xbb06a6f443f5e7b7cc7413beae3ce138d20c883d06d562a887ffe80f549168f752af79c4380f361c97964a4527b85461331087d8bfca35d32943dbdc051f0b06	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	1	0	0	0	0	0	0	0	0	0
\\x34a3f07a24d7c03709a4223fb4599c63257fd2c23e6cf6ce4013f1c6cac7b54a3da4712fdfdc72c0eb84ceaf03388ed8821a6df75d131857d86f11abf69ae13b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	1	0	0	0	0	0	0	0	0	0
\\xdb831464213078c8cf0c40da807a60330d1a1dcd10f2c0d4ff8197749e8cd9db024ad11e85dc14c6f1c9bfc756e307b9198f996282ddd843877ae3a2a90dc583	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	1	0	0	0	0	0	0	0	0	0
\\xd88c3fae35c8f1f4eaec216e1e7c47a743d7e454618a3f93abd0369e00b72307dd7337d87cd42f9d5023a6c0330d473a3561a863c1d78c4338a4cd977e6e5274	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	1	0	0	0	0	0	0	0	0	0
\\xefcd2d53a3cbf7327d9e56136b3fa45639c87843d0574fd48a3c4e03949304b0b0620e584a31e5499c2ae41b5dd7213225a89573ea670b5dfddcbeb362175cbf	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	1	0	0	0	0	0	0	0	0	0
\\xacd547935df9278fb78e38ec90db005199bb2d38f6982bfaa1e5005271ccbb77479b40c9d172ae018d959a883438bfd104e179c74ca8d70cc21addb7542ffb2f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	1	0	0	0	0	0	0	0	0	0
\\x5f7bbab90f7574290d5baeb5e6eef2f06476bd404e42bf1654e3d92a415c78273c383fd1e593e3c1244aa3a04152d59342563a46f36a901f421f12de30270cd7	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x47453b1d87a5081130ab43b1116e9ef750879486d069a0f64d549d3d3709edd000049eb504a7bd8fb1b9059c0363af217ff80b1e75434636bcd9b84a18e9830d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c156e66a273f32f6111825578b0884221647b24ca685f60c332b40bfc4f3854bb71592662a2d94e9a5dafc3393c7c47ff70b8479285bc7aa3042d3c4ab2be0f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a511c3b0996a9bde1d21c731edb78d1dc2742e500118e1de9d7a30419f821570578922f60f1d391c13134eaf40be678cca21828b3b0be8005111d3ee1381cbb	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x968a28500703ce0325af8dd6fd128b892cc244a38cb85d17500459fed111b7a3f12c6772df8ea93aa42cdff4cae2337f08016b7abdeb9f217223c10948147d95	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c3cb6b3267f0d265194df27f1ca1274fca19b6e3af2adf53189ee4e6af22128b1ff49cee313bbb4c0aac0754445c7aad1130404d4192f64d57f43940d46056a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8eefa131b1383a2cd32df2a9714fbacc6d368e8d1996c697ad371e7e3283c59f7de23649e1486e09f7989d38f4da0b630ebe662d72469715d29aa82082524533	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b0e94e2b880471a4f28a2aaf3e373efc9db5ee6f3d7bbbc5653677ef5af723d3ed119b94a581d01c62b2cf2b27300ef1187097da77de689f24c8766b896a545	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8fe67e4fa3b47303194eee10dae3776debd8abcef19e19a0d5481368502a0c74bd3e4ce1c5bace0522227dbd3bd519a2eb8238cb0c3d9f223dc860b6d8be72ae	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6034bdf68b09ded19e08f2a72e504d80346937d88d6a0a12cd6b3d70e3abdbb97639864d052c143105bcbfe9a4d6fdb5784861f0ef8312d44ccfc6dcc768dec	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x39af6d9da68826d6ab50b3699ae391bda6714f135fcd1b4abf9b793db94ebe53a9f4d95d9748bb4d28fdb3e00b040159979e6c4559dcf3078649b67dc0d084f9	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x90bf7368cafce541c0fa39fb8e87ed3b34c0ae0c1ff0fadde332f14613fbecb54602c445cb7627cd72b8d14c80c367dacf86ab8a04cf6b14f7701cf1def25f15	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x79bf64d0f8e3e81da3fea7c4237b0e798f2671b921fc18d0a7b1f14b7e7302f5a45442ff3e8c4d95e0f007f7b04968ebd2e306c0b9c37502b7f100366cfb1f62	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f99ab66965f8bbd046a340f618dfef6119a3b93664d47575a439ff62d39be3caac26de203e813d419b1eeb953e2b9a83c6a6104e7d92606e27131055ec3e019	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0442aea9463625337634d45b2d12d8d1deab0c3766a2db39bc65cefca02f623e8dcde612dccd2da808dc88d498a4cfb6804225b1e134dd2a1f5ef0db29ec3b48	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe215a63a9984d7b6aff3213528a346093f6c0c537d81b0b7a0effa4254161d6d2729d5fc17a6c200e713ba61d1195b38ac534f285aa3ed57721b235cb7c3927	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6af10383e623995637af524f9cde8c0fb094e2157335d67c9e24030c039a4e7417eb180c1277281d4f79f75f05fefe7e1b14071ee2ac4afcc3475e7a18b6cd37	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x562ecd62fc890f7fed79fd9cc13279b7843613bd40176784d98170f0855b4bf1bd783c53f2b6e322fc9f9286e82a11c51658d8a37955b5ce75bcab73ccc0ab5e	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcef812941562267bfe5a670b7fdea9eaf01750d994562253ec0a09b514847fbbe4da91b948f4e04b812bef4e797cba49bee5361ebc848511497f0575bbd76a57	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c2018724c286d79c6999a946de4c449a68450b38cdcfe664784b65040b2af0aebc4492120241d8fd868f146ec6568f7b2b21ffe5b3c77d3306880a5591c946d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a145ffd9a8c9fefa94bff24b1aac6ab74124df9aec2d878ff0bdba8c09be5872d8f9ad8764dd92dfb3bc49b1ba508eaaaba44144e39c3213dab591ed1ec74d8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x168941e8b723b9c4965f698328aba20c31054555bcde04415c62fb1254b3d3b253690e030a5fed676d4d21bb67a69d23d9e810ecb7efecef979cfad97ade2903	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa8e3f44f4d054267036b2ef7f29d5d24dc45a4afcddd7ed4e977cd244d00632b78e3a920be2856cff3f2f06de58bd8bd92340813b39e31f5ff2a71fef558fd74	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb9659f7a491caee00dc14034351be2934f8b85fea7c50bc8dd88668267254fc08c3c441d47c0038aac191ad4e7e787744968fd2f89e532ec50294032571393c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3a3d70eefc3ffb5b0fef6ebe99b6922e38f5ac977f3c58563a4a3eeea661c5f0ed2fd26feb3e2524da6200cca35cb845a7d1689e8dc55ed04b7a057bb8bc37a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2f9fd6d777b02ea4ae17c689bf41341c299b641530785e387f74feb3174557ce95d562667da4bac385447ee6c3305d51616e699c37cd828520ba3d35cd2190c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ac1e254180748ff9cc1b77d1525fe7330bebb7e22405b82ae230bf079de0a49e0fe35ac125c8ab74d453546aa491cbe24a98fe200dba86b9bbe40a09df69a9a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x039dd64fd0339cb1dac80277d504ac85601bd11fd6ce003d8371bc2ac9a9a95d4e0259ce86c8680fb7aaa61657ee4e6a9f8dc91a2e3ade7359a68e1d076ce5d3	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x810c62d4cbb8b9232659c3bceb4430f68eced6fd9041f084cee6df4b713a9d35c63905c8294030872e6827bf9dc4834263e1ec6060ddae39807683fb081e0a5c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6801eb19316526187fe4360f355fa549c0965eef9d753f462044829b70b8136cd14a272ab74e5f82080d49dde22e0d33228513b82bd0431ccf32d2ada77afe58	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3cffefa511433a5c1e6762bc86ac71f9ed305e9bbfc915303d47f0bd9d2ef85d7353b5531e409e6ed2c12157914e769865f4be8be974102561b4703509e0e78d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc4d7768c5d0a1dc0abcb1e247353dc0e46335486bd5fed9591b9b26cca96729062643911436ae4e126333daa128e2848060611d060edfdec23260ace9dbe7fb4	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9a9314440a36926d0dcca969a88ddc5e36dfa3f2c173e6dea844183158be5429fabaf486251328300271a0bcbff71fdf63ebe3a1db1fbbbcd94aa7f5c52f9b1	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xffb87c78ac19f0d05e3c9d015d5cf6343817b5d78523a13e47582fd1b9c3454872401b1377c882b347fc95bb32ba596fb42a76128f1e189139cd9ffabfa32450	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1566562629000000	1567167429000000	1629634629000000	1661170629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x4508a678d40ae3e3ddf48f3958cfcc9eee737c6816a7c0c4abe8d86f8e25194df4d066b6ec5624d437d783d555c52e6568a6a0da302bb05d79463c2dc81b7f7c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567167129000000	1567771929000000	1630239129000000	1661775129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd5e475d016296529cc54a1b6cb36c3c97e442e029dc8298e9b42221c6bc206b35521c1bba284b7db67c224d5eac99ba5438b1d4f6d4a2a771046c20cd3e22430	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1567771629000000	1568376429000000	1630843629000000	1662379629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x6db8a98da60e2ad360b57ebfe817984d21df08b7fa78e851694c43fbe6ace7e784f2c48f5f6ac533209c2190b92524d0efa0b83542da719a48013f0739b86b83	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568376129000000	1568980929000000	1631448129000000	1662984129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x5a355a574dfc8836bc407959cf2f13ef21a4210a69b1445c43e6c621fe4508a70a66634c041b2c3a173474f14e33650827096aef3c89dab5fa9f40663c984d73	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1568980629000000	1569585429000000	1632052629000000	1663588629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x41ed614e25457c97e39b40e126296ff907ddaaf899ccee432236006c9d4103566e1e71aa6d60149b3706737ac3904e91395df1a8a8ca8d19043e9212a72619a9	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1569585129000000	1570189929000000	1632657129000000	1664193129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x09cae084c882a5b9b4c19f7d02a4dae2de984259b4e378e0e15f50109522e87ac1c8f7181ef8e792a93395b560fcd41003e66a5983283de4cf42d4bfc34c2a1c	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570189629000000	1570794429000000	1633261629000000	1664797629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8a2c3873d7ededfc573f037919183876c0babbdb7f39d257260a34586fdb25de32a56929cc0f88f8990664f7cd4deed5f4ab219dddd4cbce021c88b8918eca47	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1570794129000000	1571398929000000	1633866129000000	1665402129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xc8e3056ea1164d07377226b8afaed5ecdfd815d6fb4f0ad3ef4bcd2a5e9630bfcb10fd7831ab775f22b1dd0b780969080243c5851203262d7506136af0c9ddce	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1571398629000000	1572003429000000	1634470629000000	1666006629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf7bb985d61eda2c088feeaa0c8051e5c441a82225f0a10acfaf6e1e5d4ef48530bedb105681b94c160d4980ca7a6c8a38f2a19a42d6c7b95d85b7f5c8d4844c7	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572003129000000	1572607929000000	1635075129000000	1666611129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xa700942e9ca346b33934b5fd6b19b00d5f14a1189881bbfb17e71f876c831201a9ec534ca2666134bcfc4a668ea32db9dd7080657d34b33ae36f6c8e10e74c0f	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1572607629000000	1573212429000000	1635679629000000	1667215629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xa31e48df762ffb0e8594edd729d894f11378dd94e26d1a370407ebf5ffd081fb4cd1aed673897473738cfae657ab4449c067328bc9fdb24fb026116aa34cc8ea	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573212129000000	1573816929000000	1636284129000000	1667820129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xcf404e0afc9c6ad5919b3387ba4f4e5338358505dd48d8972041158b4935f988bf3446ac2ea012e09139840f8905f61678ec3f9eec76f58c52524dec045884d2	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1573816629000000	1574421429000000	1636888629000000	1668424629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8e3998fb3d427f8b41e15595d3f8ad811809a782b4f5613c8d08c48ba9476e986b98d58b41c50a2624d0d406ed83d3f0a1679a6550566671303d0912e0acc703	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1574421129000000	1575025929000000	1637493129000000	1669029129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x9aa45a742dfc63382af2962d04a1330560b3b34e53f204dcc2af1e8f9126deab6324667450ed12678566fdf3420f9e612a1f8fbfb92bc42adcfcbf24f9c25c8b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575025629000000	1575630429000000	1638097629000000	1669633629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xddc12b424cc7888600252e85593f1a9595170af5caaf8b3d3baf2a76e5199d2313cce0552698c7c3bef7f4a235d48eba8dc9d4de3ae805d12a1e6167f0f5ba7d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1575630129000000	1576234929000000	1638702129000000	1670238129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xa49d1f6db296b135d3a5c8a107a808ddb2a9c8dbadada626548e2f2fbefdad9c02cecda1c1c96ca36c3b25b83158f9e23f2fa023b1bfc3e1b20f499ee89ae47a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576234629000000	1576839429000000	1639306629000000	1670842629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x36440cc3aba9a1781aab9cb9bb13fa730949811e3763574491f35f3b1f16cc96e60a6c356770842a1c62f342e60f9b74e4a6cfa4228dacece6df47b13d8ad12b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1576839129000000	1577443929000000	1639911129000000	1671447129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xe8cfce1ccf5d0dd84fd1a5454c5b20418f5648c53bfd2380b7af30f6a91502940e4b06ccebe9b3099234688e287b7e180fe63049fd2cee9f0bc3db4e5d3c0c20	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1577443629000000	1578048429000000	1640515629000000	1672051629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xae092721dc714657410882d7f6c5effa0caeea286111cdc22a82e8a83f7174a6735935f5fe50e1364125076da83a55eefff09d96656dbff01d89341257872bea	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578048129000000	1578652929000000	1641120129000000	1672656129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x5b45b2b239f696f81705fb5c349fa7dc2c7d8ba1ad21f6c16aa937732c0d6afdfe9d6da0029d7479935dd20b07a26355146cf41f52d9257135d42cee2589ab94	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1578652629000000	1579257429000000	1641724629000000	1673260629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0980bb66a4c0af89525ca8f6f87ede0d0bb4bafd44b6b767da50fc9ede38feb3628fde94754b03119961da7adfd0ee8f32be12e29cd6c51292e85bbc759a333b	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579257129000000	1579861929000000	1642329129000000	1673865129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x82dcddeb7fcd13cd738042d307d0fbd713abc8cee263a4a078ea418512958ec843ec57a2127317fe522e72b146f81a57f318eb585980e45b70f9cb0991a00d82	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1579861629000000	1580466429000000	1642933629000000	1674469629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8e50c446ac8359a33c953b387e4cc9b09e91e3b63487d322a8f8fc0d673be64de3a5b1ec87de4a14f1d5cda0786d364ed466dd70b5a8fc60c45bbbb0acf9254e	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1580466129000000	1581070929000000	1643538129000000	1675074129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xfaada701e6ffbea4cb3d5e1cb0225e8cf7de4ab2abc1c2e291818370bcfc4a816ece8091ba4cc735b5ab25599585dff4b4809e9c09a37170681bec73fed4d9f2	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581070629000000	1581675429000000	1644142629000000	1675678629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8314e965ed8b49d894bfbdf3507a24c16582597030f22514ffb49c37f396cf6ae13566e257d343a89995a7317bbed9bc8f1862f5f39c9519faf91028fb884282	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1581675129000000	1582279929000000	1644747129000000	1676283129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x063cf44d4bf7c0941ac9ba7c9506b65209a3ddd16896ee591b3a6b4c16ad701e86fd53d84ba5e49c349d8320ecd62225d8d6e8e0d86e09ee21b62b03b399e8a5	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582279629000000	1582884429000000	1645351629000000	1676887629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x7c2f3901f64c6bbb49142b79cc56df721e55626306b4966adeb168c42e4a964315b7bbb89ec1231f43e1ccc6ad775040f1ca6e0a153629dad4401054686ba9d2	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1582884129000000	1583488929000000	1645956129000000	1677492129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x2055c73724012ed11325c920d1f30612d61c6fca0dba427092d8ddbbc51fc49028d526d2842d0ba912448fd713647647011b2491bb2704a88fc6705f5dd25cba	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1583488629000000	1584093429000000	1646560629000000	1678096629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd01d5f1e83d039b4200468b831cd8dda99a3eba4a956e1486a3ef717469949a7b36f78a31e9d15d2e7399153000b85eb130cfe06bfd020332db79bab6d25da4d	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584093129000000	1584697929000000	1647165129000000	1678701129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x35d6b9062aaafbc66fe131b7b56749e46d495b5f161250cc6543680685e4093ee58d203f6d7c1f8d440437baa616cbbb0db5e12b83da3472df7bfa80600308ca	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1584697629000000	1585302429000000	1647769629000000	1679305629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x5c251e6a3e79850ae4e41951afc075940866fa37ffea87dcb02692da9313cd4ba3baf2c7d50b332bbf32813c35a0da671517c0caf400ffe2672a56a0aaa54ba8	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585302129000000	1585906929000000	1648374129000000	1679910129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x891374b1b0eb6781f0259dcbc7c093295c4c6ef0554912b06fbee99b8e496b43df1d6b2dfd144fb68a6e67ad3edd251bf5d01e098f355cfc72de7c8cd8285476	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	1585906629000000	1586511429000000	1648978629000000	1680514629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_ledger; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_historic_ledger (master_pub, purpose, "timestamp", balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_reserve_summary; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_historic_reserve_summary (master_pub, start_date, end_date, reserve_profits_val, reserve_profits_frac) FROM stdin;
\.


--
-- Data for Name: auditor_predicted_result; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_predicted_result (master_pub, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_progress_aggregation; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_aggregation (master_pub, last_wire_out_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_coin; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_payback_serial_id, last_payback_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_payback_serial_id, last_reserve_close_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_reserves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid) FROM stdin;
\.


--
-- Data for Name: auditor_wire_fee_balance; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_wire_fee_balance (master_pub, wire_fee_balance_val, wire_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_group (id, name) FROM stdin;
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_permission (id, name, content_type_id, codename) FROM stdin;
1	Can add permission	1	add_permission
2	Can change permission	1	change_permission
3	Can delete permission	1	delete_permission
4	Can add group	2	add_group
5	Can change group	2	change_group
6	Can delete group	2	delete_group
7	Can add user	3	add_user
8	Can change user	3	change_user
9	Can delete user	3	delete_user
10	Can add content type	4	add_contenttype
11	Can change content type	4	change_contenttype
12	Can delete content type	4	delete_contenttype
13	Can add session	5	add_session
14	Can change session	5	change_session
15	Can delete session	5	delete_session
16	Can add bank account	6	add_bankaccount
17	Can change bank account	6	change_bankaccount
18	Can delete bank account	6	delete_bankaccount
19	Can add bank transaction	7	add_banktransaction
20	Can change bank transaction	7	change_banktransaction
21	Can delete bank transaction	7	delete_banktransaction
\.


--
-- Data for Name: auth_user; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
1	pbkdf2_sha256$36000$1d9issHq95gc$EVL7Mg+AL/jv6O/bswiNXRAz//WGLubeSz+gKpEmVTc=	\N	f	Bank				f	t	2019-08-23 14:17:31.917761+02
2	pbkdf2_sha256$36000$k3hL6kV6TL62$krt5jFeyfl+f5SjGcQsDg1Kz8MK/8AReqZcGg2Jv9UY=	\N	f	Exchange				f	t	2019-08-23 14:17:31.984137+02
3	pbkdf2_sha256$36000$ZNB2uhHrunQA$GqdUaPq95fmyi1yHTAI0j2QcE2ZZVT5VdUvNDTsf4f0=	\N	f	Tor				f	t	2019-08-23 14:17:32.050296+02
4	pbkdf2_sha256$36000$oYKQBmtYqHmw$jN4Gij0RewWP/3p92NwmsdCVtd3yogWVdriRrCySLs8=	\N	f	GNUnet				f	t	2019-08-23 14:17:32.117705+02
5	pbkdf2_sha256$36000$VCxtdmy6YReE$7KORqFThq8L8Cv7TsjQIlG/wWvDM1qx4F56JilDEJec=	\N	f	Taler				f	t	2019-08-23 14:17:32.184813+02
6	pbkdf2_sha256$36000$rpLV6HfZp5ga$1XNtR35q+yMVtknlg/hv8tDO30yftxQkjtZOcjh0xfk=	\N	f	FSF				f	t	2019-08-23 14:17:32.262248+02
7	pbkdf2_sha256$36000$jmH53ljoClVQ$iUdcB0GSpKA2TnGXt58tt3SaMGmzSRKJoLlgKGTyVPc=	\N	f	Tutorial				f	t	2019-08-23 14:17:32.328522+02
8	pbkdf2_sha256$36000$hW57oOKwBXLD$GUD1tpVzXXQeLIzHAKbrpRKG7HZcg/ShI0vVBkKKNMg=	\N	f	Survey				f	t	2019-08-23 14:17:32.395166+02
9	pbkdf2_sha256$36000$O3sH4RaeqfwJ$A+ybpKCmYrprYXsTbr7xj2bsRJatSjwN71CU3p5a9C4=	\N	f	testuser-P4S7IxFR				f	t	2019-08-23 14:17:39.162456+02
\.


--
-- Data for Name: auth_user_groups; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_user_groups (id, user_id, group_id) FROM stdin;
\.


--
-- Data for Name: auth_user_user_permissions; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_user_user_permissions (id, user_id, permission_id) FROM stdin;
\.


--
-- Data for Name: channels; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.channels (id, pub_key, max_state_message_id, state_hash_message_id) FROM stdin;
1	\\xc95a97b1446c73f157f70e9fdf9495ad8b05ee95efae4268b66a2b5a1a7174ac	\N	\N
\.


--
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.denomination_revocations (denom_revocations_serial_id, denom_pub_hash, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x65eab8feb76d4a67b6f9aab5a741c015150dc59966ff1a197b081e9ed618564ece22d05e52cf9fbdfb4dbfb3c0ecda10c15716b30f26d215f539a8581d7b03cf	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345343439373838393130443543463131394333364539394432323044304541443533314533453845373035313445424637443431364331384346433742313441443246423236373242384434463534394437394443393243393534453846343942314135433143373838444135444537463732324532413142314331393641424539413146323134463938444135324545434642443835424641424339353239463142323432384446323839423442353142333643433937363433364132444243364632433933383334303137453941353638373138314239424236384232434542333137443539463335374145443730444241453342333033314234363123290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xc8d89d510320773bd72f0f74f9d005f2b15cee9a7f76be45e04ef72b95aa8e765d3f0698d92366123585b97323e6e0f9147c808a1db4d43f1d682a7ed1a40b05	1567167129000000	1567771929000000	1630239129000000	1661775129000000	8	0	0	0	0	0	0	0	0	0
\\x21798ada51e7b92f12f7799bd3232ca7b7f6a17fc672a125545dc3c0ecd4aa561731b85336d7c3e1d5455bb189d1a31a9bc70eb0073ece22afec8382cd4a1fcf	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304236383331393044354338323738324235333333333835334534303136443939324432464531364330313445333044304641453437433533314230323133454636424142433033313441443935434335413736394544353631313434453934303137373937433241303432374342313136423039313035353830413735383037443244454133373231333146344341313844384241353339383335373433434241363139373445374144414530443742383630373430463038334530413043374637303044343346434539373144314538413342323239423033433339444331363646443836343744383745424631383643463731393439354436313030384623290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xeb09844186caec810bf2b9fa13945b0e780d4382e2d0dd6453b7f9bb33d02c932e1d02178a38fb6602e4e8d729420dce4fd74cec2ebdb7d7d6bedfdc27ce2c07	1567771629000000	1568376429000000	1630843629000000	1662379629000000	8	0	0	0	0	0	0	0	0	0
\\xf191f6470ce9ab2080a0801f6e53a31385d4626e89eaa1ab2ea6c1eef785ddb01567bcede43411c104844a288f7e18bec14bc75800e39febcdfff1ac33bf2113	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304544373241453442423031313131454333313035373635364242354241333139374241364334373732383942324237303432374136344335433446333245464133373936383144463030433131394232344339444441323743353246374231454243443137373745423633433539433737393937454237393246313542334237424231434531394344454239414238313141373531413039363236373138323335373845464333453131333941353742454333364243434232414530393942324536393532383233324136464230443930384636413334353744364330413742383933413144373441353339413038313134323230384446464638353342343523290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x9592c902ae02ff2e2b285cd33fd7bbf44033787c4b54f3a1af53a2f6b04c2f35924e64935c17340a89792294f681ff6a9b10c76b551767d436efab076574bb08	1566562629000000	1567167429000000	1629634629000000	1661170629000000	8	0	0	0	0	0	0	0	0	0
\\x1304e4ae482303f0744d7982dd2ba60700909768952c8582b0fb809f71339f70b3aa34daa656067cb32c6218c302e242065178be9349b4fcf96a6a4eb125f173	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139433231413734454239363737374138334331443344393141334445454232464245413942314541313843334634363242454537333844463842324530384338353130394639464137384645433830373144373739433231433541313837453531454333463738323136363930343033333746304131353632453337394236304436324643434146463142413839323032324346443935363841363333364442394237313837413230463844373338414336373243443743413832314246414242343745333742394441363530354544444335303345354331324233463341313842433033454538383445463835433138394337303346383441364243373523290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xbf0c1bfe43b225152d4d6ac72f2f5fbf75fe9e6f62e1cee96e01baecc82e6b98b8da59b24bef5173d31fe2a96991f7e065ac6758d767b23e507f44ce6fd45605	1568376129000000	1568980929000000	1631448129000000	1662984129000000	8	0	0	0	0	0	0	0	0	0
\\x00848043a28916bdebccfd96d8008f8e51c367465789cb2eb9e3ce450b0f9bab19066c53ba0b403f945fc1c1d6df31f0fd7396a757dbfd00bc5d8d5202effc0b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342464641303530393438394643353335423942303144353234444134463732444333394541413343353345433645453237464242343441394537383733354435314335394536464533423844304135394144384234323745383033303934423938454533424534344433333938303842433237423131423844323644443430343544363342373537373836424231374546373438354231363032423539433035424534323642343330313438334633433745424633433041424342433541314431343731343334443046414643364533454132394633463742354641424243323734304136334535303031434444324344444443344543413846343541354223290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xb3d0ed9cb384476283ce56d383b288d527217eef256bea51cd64f6cc8b175debbf258ad0262591524fc2d04c0745705a76b728c6b865da9f44b6d2ec634a6a08	1568980629000000	1569585429000000	1632052629000000	1663588629000000	8	0	0	0	0	0	0	0	0	0
\\xa511bf15b6e0744bc46344cdba28f9acfbc201a7b11a781240d0dd34b619b73949da62477e8f04b7495bdd3108e096496ded8ad93dddbfa669d32c6889ce1200	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304432323433453033423641454230314134413543413736333042334546434445334242423937303039463530463944333530363332434335343544464433324441354134313134423638393745374536464137303837453343453130353233344238464132354133343437313838383843434432343846303031353539303630304643373534313638333435374344433933444532443346413430373043324632413536393233353343413533453444354145414135303946343137344246353542334130353642343743323043394234383339334633443236324631453431313133304245324332324246334446354344353338353846454530333237444423290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xa80c9df5ddc96a5ccfc2365487a601402c87f09ea27314a8f24f86565c60a95e3686918d61d69c1e90a4bc4febac80cbbea3f9ad0f5c2c6024e1a3bdf7b15208	1567167129000000	1567771929000000	1630239129000000	1661775129000000	4	0	0	0	0	0	0	0	0	0
\\xeb724b4b733105f43674463f8ea6475c45acf3772e145c56eb760fb2027edf517f8e8ab89948106a15ed27f27c81e34187eee4438f80350543fc62258a8b5dca	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246423346304443414435323931373842323130383941344643384130363842453639444131363532333634304330413435354639394434413146344636393438333933454244464442373445353742393838423835453832353042383235324344393145433334344638463639373536333432333635303035353039334635333239323743314138383433303545374633464636443630314231443935363141343936323143393034313931444130313744314536434445324339304130333637423836423743314438413139394243324645443638444435393934353645364431414336314236433044413735313134463742413138334638324135433523290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x7bef927b8e75853dd5e398eb9fe8577e15158635533fd39dd358b8445213cb2493020a977826f83df7acd275d8cf9cbcd72d5510faa13db008c21f956154c403	1567771629000000	1568376429000000	1630843629000000	1662379629000000	4	0	0	0	0	0	0	0	0	0
\\x26269c80a6adedb06a7aa8505cd4ea51e24c9cd45fd93f2cbec6d75992fdfcc2f92ecb255daf08b59361adad27789cc32cf5e028443a75e11050d876a4d8791b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304446373537343634374231333738463435423935443546343644374633353634413630354338384442304346343046344437414334384436334538384439354144463445354239384238353844343536394646363344453331444645463635433431444646383641423245373644363137343436424644343146384537303545383730363141433844384237353546414446463044413531393230393846324333303734423345423338363738434341464430434536453330323541423546453632464144323734364137344232433237424344393730393531303835353034393044363242453441314542453731384437363730433844414531423841313723290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xbd48f4628e1ad7d991e1b780d1b30780a0ef1a03e360607d6495921d8f1e852f19800f652bbd26fc394be71dd3bb451e4700a6e2ecb95e3db23487c7b448c30c	1566562629000000	1567167429000000	1629634629000000	1661170629000000	4	0	0	0	0	0	0	0	0	0
\\xc4aec9fc286def17164c6ff99ededd2433b75e9a83bc44cb0cd172f271d9ccbf71b1a612b555b74cdea4f24d8e7be90f5b3ca5f485f62c88fe25857f8f67c4db	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331313541303934373039434338303244323435454130424535444545433131373946443139353539384631433145353642353733304637414637373837343832433533463235314539453834393642334631343135334336323235313144313839434634393136394637444445413230314433363345343646384435433333433543413337363641323237453132413042373343333534453142423531443831343038313939324331394535454346444333463042424330333132343242373542423945454643334445453034324145303030453346303432434436334232373434433134334336324635304342314646443734394643423632433232344623290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x2e67201d5d16a69df09c5c7900da4e89eda12ec47cf531fcf0b6836ec5d9aadb6e49f4892cc2491b2ff088f8cde72eeecc36f3e2c040236f1f77c9615604b801	1568376129000000	1568980929000000	1631448129000000	1662984129000000	4	0	0	0	0	0	0	0	0	0
\\xd8add003543f060b5ee3ee26262d6208f96a8bfd3f52ae53e502377083b696e7ab12f1b791c0df1dc5452dbb55aab2fd1c45d05fccd1714af3a3a7e7bb98a402	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233463436424238463331394546363245324436383734344642423135334636374634413034393936353042393041373446444546354134373239323738414430464235333331383546323637383744334441344638393944433941343846313034464445433644454644433932383243313742444638464437304442454332453731423841344634383635374636343942314334384238324346393231394446303035363533463535414241303045393744353737444634444432444530454244354641393141304342324631334337383334353733373433344536333530363331373330434645433731353931333037463439414432354346423135314223290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xa30c0fdc59bf928c8e248783bdcc482902cb9fd87a9b808bf173cfe78eba1395f50c2185f84d3271ac674164bcfac85a67e4590e4f4158701502958f2eea1203	1568980629000000	1569585429000000	1632052629000000	1663588629000000	4	0	0	0	0	0	0	0	0	0
\\x9f99a47d1c1db3f2f30fc6ecdab86d4eafb6bdc97ed631e469d98f4a1f1fb2197a2020e90d4c9115ddeabb8f370873db71e4f14e9aa89df57fc964d5823ab460	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436433035423038384241443432374332344144333646363235463132384444364331374646353841413037414136334630374133423638303336353634304539313944324531374237384335304637413042453745363230364531393246423846413443433237344338393742393039313438303730303443463232423942374243323346393046344337303937454230413941413939374541384334364146463632314430433433394530444636383331333041334639443131443538444337423635334432334137303646453436383346374534463941364130333939303737333934433532414641384442424133303533363035363437383631424423290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x0d50b2180600e8806dcf75c07c4e14a3a34884cdb3dbec18cd7d8da322b143c3b847a9de631943891f4e6ea3dce12edf6117721362edf7e974af4e3932606604	1567167129000000	1567771929000000	1630239129000000	1661775129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x025c9bc02f2b5cff41d6b9b9aa864f1429ca98b4e13379bee5c72215eefdf79b8812a253ad8e0fdda75cdd4fd79d3b471084dcd95be8d9a3711e3f79ec580bcc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304641413030344339463046353034433045434433433035423138453633393135413233434144373034424138353941413131303531363745423946344141353234343233303733314431383037394241374546433736423436364244374441444330303143383539423246394336433033323643463832464339364238454641384532423739333635393641354439364532453046303539353144333244323746373444353845444433453337353137454631363937354245414144343631443637434531363146363835394536304137384546313843464141394535423446433134413643444232364243444339373430333243323846394138453842424623290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x094cb005d3d643e10bd61472d2c407abb0c54898bab8adf03591b9b6835533b391a01de5be29c809287df9284ca06da195dc6f1989b7440ccc89078fa31b670a	1567771629000000	1568376429000000	1630843629000000	1662379629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44a7420cd0b596e057770c5fe0d017c8986c75911b1bd9795dd09865ddd632ec17213572b46df28e6e46b6fc645880ef6f55dace558f773f8b07781f4907fc86	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304642463830304444433938363045313339463245423438354245323244334636423630434343373737423641393241434342333732303031334644413638434335374630384537343938453731463835373039323344363333333545444634363634353435433134344646374235334246344543363542323545334641303742344645443737314437394632413436443746343439373230423946433634424131414644354632303034364139303034334235414243433035313936353235374339343135383438323337393236433131303137414642323342443339373830303044304343313244453932393833373744463337353843373842313533413323290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x8e766d06140d226d1bdf8007f27630bede3e2a5e594ebc9485b96d92ee5fde94f1fae16d2d3d8ccb3cff297bcad7035f22af4bba58579c8c285ee5c84c87c309	1566562629000000	1567167429000000	1629634629000000	1661170629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ee3ae3e211cc19faa5f931a63886a5b3680c764d82cb85f34d7f32683d4801773a6aa66b1fd25088cea19e2726e2bd5f2998e3e7a95f7d1890b5278796cafe9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338333846334438344543364539323542463737394642324139453441323846463342463944363345433643383134373444343143323433333746383434353645363638313641463334424432424535343130383146303731414241413630463942463944413342304245304231364634343644323737324142353930424245324642453137364232464545423332303939433939413039383538363337324333414230343543433639383735353436464430393537444443393531423530424331444238393244433035314436463146323941433037433830424146323237423237314632443641384637363536383635353139363946463441464345383723290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xda46ba1ce8cb8d5f1c6bfcb9167202dd0b2c155647b022437f3471d2ea14cfab5f4047c9f48f947780cb2911759e73ef14b8b5db8a528409430a03088ff57703	1568376129000000	1568980929000000	1631448129000000	1662984129000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c5e8daaa1cbe15ca5b4616f13b01057de4a3e63c22c2f9492ccabcf8b3a722317d12d122f61c665f2c1050f853696c6db98bcd2fec1af33d29efeb9773773a4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304346363746454444444130304141413939463336434131464444423643453242363644333546313431434635463639304346344634423432463744354432454644323241324545423431363744423930423642374543423845323246453435423736313030343234463335364242464341423235423242324134444132383241394143393045334645383739324341373832453934383332383633333432343633413345304542303434433132333238363042343945443542443041434445424544434339434231313844343933414244393239363038454335353241373438464542373435363835383336383939323545414144394636444642444342354423290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x0a2b41c062522aa7f8ba30a1393323eaa6e13d1c39f9828f19c883408cc5d5389062e592cf754f4565aac1c4ea9384a0e8d178c4376580993df98d47246a4307	1568980629000000	1569585429000000	1632052629000000	1663588629000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4508a678d40ae3e3ddf48f3958cfcc9eee737c6816a7c0c4abe8d86f8e25194df4d066b6ec5624d437d783d555c52e6568a6a0da302bb05d79463c2dc81b7f7c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342364646343742374339453035424538453534433641383232443531364439314233393736354436383438364442353031303846323535333835394245443631453443463836394131454635464632383035443243393032304442393545314245373644454141424643304133363638453646304344453932314430423239304134354444333444354545363833364645313146363035464339433533393944374543434133354435453041443438343443323734364336303532343935393646454232423446394243433438303046383842333642363833353134364643364632394245364641344137444530333739423430394145303431364246313723290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x2c2216d2d1ac2a81e0e70b5dd42a97c558b9fe8d138d233be50b1553cce709953b6a7d4e512c7f8a18af9b537ba6da204aa5501719f5ed5f6b6a1a6a95e7c907	1567167129000000	1567771929000000	1630239129000000	1661775129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd5e475d016296529cc54a1b6cb36c3c97e442e029dc8298e9b42221c6bc206b35521c1bba284b7db67c224d5eac99ba5438b1d4f6d4a2a771046c20cd3e22430	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304344443641364330324644383634374137424644393331413346344537463546373138443936303333384130353733364333343038303236444139463444433542343845433044314144354530454545353046374430353136423244463138363846454635343630363131333831433339343235454543453342343345433731443944463043394132423639334145323933354245444236304438304235373246354434343837344533323644384239354444383430433742443639414243464445444631303544343430413437453046464443303042323345373230423044353036384639363133324535423343333137434446394535343530374139364623290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x8f269d4dd6851808a479a040d348c8a06740251ecac14dd0beaedba4cca85f487e2f85c2eb75cb2f83fd07bab5006751ca7750778f5f2b64ecb00e96e1ddfe0d	1567771629000000	1568376429000000	1630843629000000	1662379629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xffb87c78ac19f0d05e3c9d015d5cf6343817b5d78523a13e47582fd1b9c3454872401b1377c882b347fc95bb32ba596fb42a76128f1e189139cd9ffabfa32450	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238383730394439343146363437413030443737314438333231463038414639443339343246433336453344383035393837463137453538363536314439324541373039413730343644444142384333414546384134464231343933394244424332434438423736333333303646454541454337363443323146443643454336464533433933443734353546303439334636364132323533363337414335364331323633343545413832313942354544323741444637353736414237444231374344383241314244314339464630464436454633423531433441454637463434374130383938423231353143453833433743354241414143384333374433303723290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x54d9da09393a7c151d49d8904f47834bff6e83dd019b90190d25867b474216c95e2a815b243f74072128111b03ff35c9e8a341057967545b9c3a703a4e856203	1566562629000000	1567167429000000	1629634629000000	1661170629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x6db8a98da60e2ad360b57ebfe817984d21df08b7fa78e851694c43fbe6ace7e784f2c48f5f6ac533209c2190b92524d0efa0b83542da719a48013f0739b86b83	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304234444342454242463044363837323531334345364643464238454345393044373034373232364234303136453135354244423830464633363345463030314342443341313130414446454632424135383034353833383439353133353233334231444431303841303342464433363635383142323838304545413943363831433844373044453136303239374445333743323846464135454333363130324234423632354636344444463339444132434232423130424637363041313542384141324632393231383130464539384246423736343435464536453544383643433945433043464535383239304234364342393537394245433944453731373923290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x8cede79a9d0489699f7c72a53beaf32f55afda076bac9635ccd824dca9e5b2137195299cb4f058a9f615d7dcdc6b06e3da9ab91c5dfd46ae92ec3d08f89d310d	1568376129000000	1568980929000000	1631448129000000	1662984129000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x5a355a574dfc8836bc407959cf2f13ef21a4210a69b1445c43e6c621fe4508a70a66634c041b2c3a173474f14e33650827096aef3c89dab5fa9f40663c984d73	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331383444303934413342374635343633384638353643364143323137304433433138333736463332443935454242423542353434423032374641304638423038393845313434354542433334383545323232334631364246373136313231333936424431344231423942324545364138314443354632303238314345354635334132343341423434323931354446353332363943433631334541364334353438443238344245324242433731443130323541373544423332454236303245383838423643443241453935354237454242383741433843323145373330333543303933454238443238303142453339424145343236423432393441373746334223290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x88faab23b7ad4704a861a519038e2732cd6558a87f564189f4f4f629ee11e8e42ed6d91b2589ac025d3e1c8b51487c341de1fa9e4cc15708f72c08009145fa0d	1568980629000000	1569585429000000	1632052629000000	1663588629000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xfcf5bf5f62b051b8b8434abfd397a12cabbe1dc4d77e00d57982834267729d080facd7d6b687059982ac59379abcbcf1a7eb7a92b07a6e708e96f40edb0ef85c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304630434539323831423339364539424246303444444441374234443938304237443437384331453633333532383736423243324239463946394138393733363335374431424642363331323346374435344441323931303036364444453944424446324133323435464236424345344137393539344134464232384134353945383632464441344542463539444442343930344445383230364135343837394233414539323834313439433846344341353235333534453638373730353241383036323843434443303045393945443445344646394142383641464139344444454545363930304245314343364445433332433743323139413441363946393323290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x03bb19f2ff5ca0844f53829d69122644a90327dee1866c6b6e7676bd65989e7a4b8f533328597fba7e38761c83406873fa0e757385d63ffc95314f7581ece70a	1567167129000000	1567771929000000	1630239129000000	1661775129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2004c40d9d41dbdfc3778647894a836c4a914ad12c08405671d8a1eb7620f899bb1e75b1b3026f11657b2aff47985803923495cebc07e1bf90bd9708150ff331	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304341344539333244364143373442383139344444324645383144383646383138364138344333383232313837333445343336333430303344363736384230313536364338343739313730374639423738323434453742353146413038363730393930383431454232423543453544384334343742314145383838323838434537463343453332363142393443433545394432334138333943434241393641313539343446433839433544464636363036423338393136433044363439434231443338304135433231374137393832464337443436333534343341353442393934333339433033393241333143334141333943303835444145304237334533434223290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x17390906cf2f0884eabc01c8b992d60ab1390bf2118d3b490b2a6d0dee32925886d0c06e2fd27e8dfb4117a32fbf7a7a7adaa17889c00dc164a4141f636eb904	1567771629000000	1568376429000000	1630843629000000	1662379629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x45ab235f322f4d6cb801e27e5e5ff3c39fafabc5447df36dae59b14b4276214d10b8c2a0c40b3cbb87e38a9b1d1ac78285f96781e243d65a0e6044f7c7601f0f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304438393132304242384430363943363732393939353639324137323137323933314641323942463530343735463444393744433738303039443431323033393941433336374445343541313633353042333533333842393738463946383233453742444644393738383333463443413246383531433130363030423437384430353046353537343830344143333936384438344239414144354633463143444441364136443532313338443633433743343135314132463945453046434434334437394337373237343333443337383336313831433233444645454635454543424132344536314438343245434142453841393336313542423332373834334623290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xc778012ffc9664dde5f65a7f46093c9ef1d6a46fa00439d46bc3802f43f4e917af0ef7c8a30d7db2bf57de8147401aa8e372c4c38400b02e4e58ae051fceed0a	1566562629000000	1567167429000000	1629634629000000	1661170629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5bc7a2be153f02d623157755310d5f5578cef9c1f700d69d7012c78e6236bfc1f19bf2a112557145c4c29ffcb59325a0c0bd64ce2ce692950110e11356516ab	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431414130433238354332324431413833363332383533334241353545323739313741394243333046383633364545314539434131463731333935453944343146303542413033333444323733314146303843314146454633463246423637364446433937334131374246334332433636463634314241373344314531343238354643344444463934334241383831383246343838343333393531444533413137453432464632394138333343364342364542344337433945314346444133454639384233363434344442384639413532453032383132434142413544344333393545343439373338433339334436333042374244374443353031413134334623290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xa37d9b4164590c8083f61b4dc2b0ce5b015ff4a233de1a74d2230c529a7153627bf44865296edcc57ed4a5f7bfac54ef81bf7d43bf910ccde6ad6ec78a0c3b0a	1568376129000000	1568980929000000	1631448129000000	1662984129000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17496f47056dfb3bc9d1d216f2b19ebc9ce0428d114018ebf43c2a2f4bf7a4631b701b6eb18cc6fd471955c9475085dde983a28441b58a52a15ec5f505f34b66	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331363133323237464446353946364544383144333437454233314539383938324646344136443945383532303533384539414342383045424631363446353642304330454238313131373731414539363139414538303734353835433136324541343439393041314138433030334132453037344538373341333143453231433530323342463530314236413036453744334145394143373043463246433334383734354341343039343433434335333346433239334435303142463238303834414230373045423837414244463339414636374342354242314437373534454433463731444431314435434637334439434545354344433930433239463723290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x0e488398a7c85d5a885268bb7b9bf4269676fb88ed8b47512ee32f1382e00a4f73c6f1e05295103a7afc560d36d28f9488f1d4fa940a21ade2469b33e09d1502	1568980629000000	1569585429000000	1632052629000000	1663588629000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e17d8f92c158e2afac32f9354d5c3fe1401557601e4ba0a3d5c7e282e7d17ac66d4ef9405c9e4ca1d67f66e4454a67cb88ba9fc6a2b8f0b51c5ed5f87a12dba	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304145443044363644383141323638413133434431413844434538373534354345413746343642464339383646453239333942413931393931423742433335384144353239464136353439433439393043333642373846353346373642344334363343323742414643334330454344463344323932363546384146314635334645333244303638414341344238363945394133453937343434434431333845343833413031344432303135433631464638424232383637314131393434383133303338343137343641413741353942343730423333393630313636464432424331363941423842433333453033313736363530353130364636334639434143393523290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xbf7df529890e535ab79346a9c14177397df5352dedfde2803975599572af71e425dd78e47d0ded08591076759aa60f445c9ec27e4ba92bb825113e8731a6b707	1567167129000000	1567771929000000	1630239129000000	1661775129000000	2	0	0	0	0	0	0	0	0	0
\\x15be992d006b1e2ffe99c5e93014c71e36469566df02cc2eb5c3d28609d014da255d28d2b2644997514359bf79c32cb9782710952a4316d12a187eceab65cb25	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304239363637363643414530303034373241463637394232323538324642314546393931304445463932313446453239463334364633303645314533334535463541413031453744393839383837334344393637454539453646394235324343434546323538414645393941413843343141443339373739414131393043433138394538383732353536303332414336424233453431363637453741444534454530463831443534363443454444364638363846353437433243344633464337443135324342413639393130424539454535314236433142324438343742433231353633323136413834393943384546393438304237314538384433453436363723290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xca484e9609dfb46c3fdfa976f648b280551f4f33bfc4d9ec0ced2c22e8f138ea4a4505d17c58066b9caa1dfca79ac0ce3438dc7e4e597319cee7252c5dad5600	1567771629000000	1568376429000000	1630843629000000	1662379629000000	2	0	0	0	0	0	0	0	0	0
\\x9e1af932e98982d1941c48ec4e1326a3bf4b7e68a35e6e266a2ed60ad51977e8e5f98ffa275503f73c5647e51c46493a7a31f140e93416416cd503ae64692ef5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333424341373939443944323333424237454546383646333246414344423432453745453835384636443445434338453231433036413643334245413843324230453130393838373539454242453743424338433441334333444141303839424430463334434532433731453935374244363443433343393230444535384233454246363745363546433243354139313233373541353439413236353836304344414246333144313245353436333631324446453742443934304543463430374637384138443143363236313234453637453835333939394243454137443246413641453241414233454544394442444237334539413938413943423243303323290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x0f6b633d3e325e2d4010fcfe1151dd4ea7191565d5a48f5c8501928291d533968856d4c6db4628f405ebc8b7393db00089027f45368d311c40ebf2084e3cc307	1566562629000000	1567167429000000	1629634629000000	1661170629000000	2	0	0	0	0	0	0	0	0	0
\\xaa495703aec79efdc93d9c482c378834c28eff1feb5def47c3c316ace21c8b10e522172a030937081d3bcb8987824f37ab7e5e7416e6089ef60ea3bebc27e12c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242384635323045463939433733333241323646364231453636413232384544453535383134334535383639443039344536343132384142433836343133463945313044373130443437334344373033313038423345433141423139374336333436303139313245353941313243383239334131433144393230314335433141304245364532353430414633394433433230313234363430314239343242324438324236373639444136453639413031423931303646363843323832454445353341383332354546303834434646463941433538333736444530314630343638314133424236413532333930363545423246413036424442303130303641373523290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x1edadfb1c564096022c51e80594058926f3f46145b8d98db48807748f44289cceb1f3b40d1c135eedbb5e41e0f63934975213e5f0dbb82d50f32ec13e280a003	1568376129000000	1568980929000000	1631448129000000	1662984129000000	2	0	0	0	0	0	0	0	0	0
\\xdb15fafb8cf70c947a18ff4cdb9f01cde8a21adc2cd58bea8cc8a346f757363da21185d9dbea1621a206f3e21e091271e407f0160b52538ed9ba7244ae4a326c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331364236304332423630324544373431384336423430413438333330453538334536303138363141313237304632303736413144313341463736353133434134383546443437364333423337454533444241463541353241313237433838373235373932434639433331373338383436353232434435443639443434433937434534324143463042374644304346343137413037343646453237324343443339364136394431363142313131423636443839383045343044324142424431384345443842463033354446394441393145363042394632364144333244363943423236413745313841323637314643333942323643323737364235364138303123290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x9d202cae4c8734354fe708112c44d70f7d26b4a9293639244dbe2353c566802bad898b1c3828f8f68b74e9f038c824c50ed4afe076219c22fa78a1726de9ba02	1568980629000000	1569585429000000	1632052629000000	1663588629000000	2	0	0	0	0	0	0	0	0	0
\\x5592a06badf9e47ddd995c2c4a5521ca864242baab2168762e6a3366f7c43aa470f15495931aaaf8fa6f4425a6ab66b5033f8c8d358de1707f0aadb26790d9b1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338454431304643454138464434323633383539304343394343454435354142394434313934423541344343433338343742413337333642424538363339444138414441433043413632424145343131353138423134363843454239434642393645384441413038454533324633353339424433453537443539413636384338393537314330394437334344353743463244413435454243463130424333304430324233424136314332414535423231383235323045383536384143334333323643323633343541343036344230374230413235463934433743423044424338303732454636373135373044443937444538313232424635373030363843373523290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xbd7a9a7a93f8395c4a87b785d3ad3b53e5fed41191882db37400e8a00cfd4419bafd7bf7e413b2bbdd1c2cb9ba205c1884623a3a90c1d65b7c2db72b5b592f0f	1567167129000000	1567771929000000	1630239129000000	1661775129000000	1	0	0	0	0	0	0	0	0	0
\\x1d982dead6b50869aae976a27af12d17e409e4292473bac6f3a041a6d481595fe185c8f0903c0371217bd5236995e13314e42716c1079ca941d43b04c7dc044a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304337453732313044374539303545463144353036323142453246444538323445323634353439414343464438414542383730323930314135393231434630354438364330354343393333464234313046304432333946453637354633314641413746344330433439363930424534363544353642353041353745323841314344343342413237343434363233334345333935304345413934423731313639433633344533353538313433313231434533423737433238443137323536354346363133374538464238353435464335303142394635434542364246313436343437394639314535453741314345413931373231424635333038423345363937423123290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xca0f22ab9fd2e6931cb81bd129de5f4348c246d5af9d3c7c07ee8ec65506c2ffa99bb9955b7dedc4fb06e9e9aaeba0f43be8ed0bdef0ee16f03d69009597b900	1567771629000000	1568376429000000	1630843629000000	1662379629000000	1	0	0	0	0	0	0	0	0	0
\\xd36bc87543208f087bf1fa76c3e82dc5755897ea0c67167a4c4538a6e4830b2b03d9b28a107ca5ce6e712750865fa9b375987121543b068f9899a5675a052b3f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304344373030413445413138303433383333373141454131413042464435443239393841454646304338433635363439313741453334383945393733464437434443413045464431463536423733433530413241343345374337394344343530313345333539393942443331393244384133303638433444323132444141433536423846323436303132393741364544343146304646423932464236433633434445413743353642303732353343423730413736414146313038443346463335373836413044424541433333353634323134414534443637304337333843353433443741423444304441423441464342424546454435384643453141303735363123290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x3adbc3bed769f6b6d9af994f568d893142856965fae082abc031538c80ecb8b18004384423cf88117be09692fdb0d4a2de241c224085ff92e0c0c2595221140f	1566562629000000	1567167429000000	1629634629000000	1661170629000000	1	0	0	0	0	0	0	0	0	0
\\x7e5b2e6babb6752f44cfd139a7516343efba509add6010fec9007989467cb7d157bc65ab25dec9605650569dea927a9c64d444f7706ed82dd654bac96ea65e6c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304537373933414535353042444641313538394642464137363333463442424637394246354333453439453838413938343642463541324530354141443230443544324434363638343431304144413844463733364233323930443645353238343630343031424238424134354243464331384242344437314333453032333432393642454639393338303130413133453641373336363033383236343842314645344439353730463536453235454232313435333346453443433844343539444545344338434634433644383245304434434139453843383333344132463030333638413730363438333334423542394544454539343134424446363934464223290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x1ff311203ec0d63a59cd34513aca5a82bacc3fbbc0f56cf0d03535136d9fe6a05ae1164ff588580e9d582b2fd8e7020cf54a0c6cd876e7a84d4bea8e1d17cc07	1568376129000000	1568980929000000	1631448129000000	1662984129000000	1	0	0	0	0	0	0	0	0	0
\\x38e73dea344464944b1ea20b426e561d6dc57cef3144e2e7f56a9e5738efa1a9cf7da7ba9f351fc41b141bb046f9647b47b5f95383c7bd2900cdaeef81ddd20a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304432334133313336333135364632394644383730343642463333393145313539463330384136414231424432324431464537413833383641344138393443374534463745373645433446463843324630314139374435373037323646393431353241423232463236463438333237314437373533333146454145454441333233314635413441463936384137443337413743353135464234424542413130343746383636364533303335374533334330433031444134443130303341394343434141334635354144413336433133313941423843443835454633424337363946413737334146314541373633414543333343384530393843413443354638304623290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x1bf11862c380c0bd6f9f1682f56d0c931f8ad6ee845775ef20dc0ada34ad8ceed2174f36a5af72a0512feb6075e792d82eeaaffe2a4cca935d51d90a2fd60e0b	1568980629000000	1569585429000000	1632052629000000	1663588629000000	1	0	0	0	0	0	0	0	0	0
\\x47453b1d87a5081130ab43b1116e9ef750879486d069a0f64d549d3d3709edd000049eb504a7bd8fb1b9059c0363af217ff80b1e75434636bcd9b84a18e9830d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345443637434444454645443842354234344539464131394139313732373135334245303030383942374236393442354630363645313834393341313534453639344435303233454443353044354233344136433336314236453936413733393139344432433135433244383242304645333635323831453033393731413437304436343639414430453333363945334531443744454343413842304636423736423730384131313930433532373231423836334341413841374132383539383832323143394642453443323230383735453232433332334643393437464144324431433830333546414641393345343538303539343743463144314632303323290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x67fc3610dfdfb50f24e93dd7382b171ea6c1ffc30e3cfa8ddcded477539e018dd4c089640920b7df421965cc1bf02ed540702d82a1f316eacb8c9e107eca7108	1567167129000000	1567771929000000	1630239129000000	1661775129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c156e66a273f32f6111825578b0884221647b24ca685f60c332b40bfc4f3854bb71592662a2d94e9a5dafc3393c7c47ff70b8479285bc7aa3042d3c4ab2be0f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304245364130323146303833354630353841453231423542394339373539354338303436443738423638324544323644453042303039453830453939323242423434423237434541444245443239314339384146363138464242423542314442454635353734343532353241304645334333373834444546414546333733383546373245383142414134353541374530313737313435464231343836443645304446364138353743444633413537393643303638333532333533433134384230383445433636343536373830303341433135324144454335333046423230313939383034443345414245383534313946314638393242333233464136393131313923290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x3008520cbe0fab0f153f3b94c64241ee5e21b7c0fe011f3c8fb64f7493639fff156313d2e29d36e4ff76c035fd1e9a4ea09411ad0820d43a945ba28fb13e8004	1567771629000000	1568376429000000	1630843629000000	1662379629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f7bbab90f7574290d5baeb5e6eef2f06476bd404e42bf1654e3d92a415c78273c383fd1e593e3c1244aa3a04152d59342563a46f36a901f421f12de30270cd7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244314630373839443835344441383232433444363442363145333641324537333439434141413541443442313437393644364438303646334431374543393630344136374443463237303935353432413235334330373746414241363230303144343638394434394531314335313334373344414337443644374632444139363443303234434637303433353944344143334338354636344530363242463438453337333737413837384143374333374241384539323143334435413844433430383946433642323134344136383142323443363936343038453930324635343035353346424343334130333941413237453142353132313833413441353323290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x31a22541abee88508f6cc98bf4ec8bf81489a01ebc7455d6fd8f44c505fc03d248c154fecbe474604f345ec61a3cce353b22387934f589da50918cae457c8f0e	1566562629000000	1567167429000000	1629634629000000	1661170629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a511c3b0996a9bde1d21c731edb78d1dc2742e500118e1de9d7a30419f821570578922f60f1d391c13134eaf40be678cca21828b3b0be8005111d3ee1381cbb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304541423230433437464630354337363532393341313531443432433839334236423931324141334239443532463741423146363639434437393533394531463130353932363241374530383130383731323836433846343837373339363444373731353046313636334344383838433141324241303843303932464431313636453035373430393239463146354439363939463233343730443234324646313830313035353639373539313443424642343830343638363534314341424633413932443435333438303643463945344431343332313633343145413046313035434435333838463639424543423237464434433333373134423343464632343523290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xf7038f1e26cb1d8bad362df6ef2793aef9baa483ed06fc2729474cf57b527f79a4dfc9912deac8242badededff4488d5190132d2b3323256114300646236c807	1568376129000000	1568980929000000	1631448129000000	1662984129000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x968a28500703ce0325af8dd6fd128b892cc244a38cb85d17500459fed111b7a3f12c6772df8ea93aa42cdff4cae2337f08016b7abdeb9f217223c10948147d95	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430383734323242454341414537453237324433374241344237383545433534393235354644354345423645304543373341354333454534393041303934443538383537323444463145444345334346353037443341373436413934313942414538394642433643453741454234303233414234344644453043453037463139353145463945333939333030303633333546424239353738354443423145454631463641334245353832393931383443394432393037354237393641353938423833454633324443313133413145373232423035433436453033323341443342454330443637373342393845394244363538413838443932433934314341373323290a20202865202330313030303123290a2020290a20290a	\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\x0763fbfd2fe31975e5271a88bb8027ea680d9648fb06396587d6f7316e55e5d7462179b59395d8a0b11e2b75c2636863860129a6d7c5ae02d1248625a4797b0b	1568980629000000	1569585429000000	1632052629000000	1663588629000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x8f8ffcf3b48c4121626cff3a20dde337dc6271549e35f55a9038db2289909d41	3	0	1566562660000000	0	1568377060000000	\\x33f85ba6051b1884d68cdacb715c448c19ac07a0add265e67ee0f52c0741f972	\\xc7da1b6b9b7359c608d72f4d6ec393f0339af463c0c8476d6fb82e3f4593d7809dba9be4578480d5a057fbfebc206e5fdb1bb6eb432cc7745504d6eb44ea83a5	\\x24b060c9d44143624e02398a2935e42ec29e89d33fb24d9889ffa0c30dff49d432adefd179797ec8ea17410e4a7c2b9b360b35a97935303035ff8254dcc243ac	\\xb195cdb5cfb87841175c47f73f537674f4805881f4e676fbac0da04b255c21f0dd4f1268a2ee152cb06c9acf8a7ee11f0f339c6ea555df720773abf932d8e20b	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"WCH8SRW7EH0E7GF18TAWDTV3MR5VA3AW73KQRP6TDFYJ1KCQ5N4YBN87FVTKAMS0C6AWCRAFTDYDGHWZENMYHC02ENAHY8CJDD9WXG0"}	f	f
2	\\x5b427d21ca80385b38a8c5d88d0e6abb269d15a9a8546d87a4908237c52d654a	2	0	1566562660000000	0	1568377060000000	\\x33f85ba6051b1884d68cdacb715c448c19ac07a0add265e67ee0f52c0741f972	\\xc7da1b6b9b7359c608d72f4d6ec393f0339af463c0c8476d6fb82e3f4593d7809dba9be4578480d5a057fbfebc206e5fdb1bb6eb432cc7745504d6eb44ea83a5	\\x24b060c9d44143624e02398a2935e42ec29e89d33fb24d9889ffa0c30dff49d432adefd179797ec8ea17410e4a7c2b9b360b35a97935303035ff8254dcc243ac	\\x47bcec6c011eff288cc6808bee18c298cc864fd20040836a4bdb842a328b492ce7c61f598753bf5817587f0fae8bd91e2e5fd16a791bb980323e6e37f0b1c701	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"WCH8SRW7EH0E7GF18TAWDTV3MR5VA3AW73KQRP6TDFYJ1KCQ5N4YBN87FVTKAMS0C6AWCRAFTDYDGHWZENMYHC02ENAHY8CJDD9WXG0"}	f	f
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.django_content_type (id, app_label, model) FROM stdin;
1	auth	permission
2	auth	group
3	auth	user
4	contenttypes	contenttype
5	sessions	session
6	app	bankaccount
7	app	banktransaction
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2019-08-23 14:17:28.658116+02
2	auth	0001_initial	2019-08-23 14:17:30.541983+02
3	app	0001_initial	2019-08-23 14:17:31.116756+02
4	app	0002_bankaccount_amount	2019-08-23 14:17:31.126904+02
5	app	0003_auto_20171030_1346	2019-08-23 14:17:31.137963+02
6	app	0004_auto_20171030_1428	2019-08-23 14:17:31.149069+02
7	app	0005_remove_banktransaction_currency	2019-08-23 14:17:31.160182+02
8	app	0006_auto_20171031_0823	2019-08-23 14:17:31.171296+02
9	app	0007_auto_20171031_0906	2019-08-23 14:17:31.182408+02
10	app	0008_auto_20171031_0938	2019-08-23 14:17:31.193532+02
11	app	0009_auto_20171120_1642	2019-08-23 14:17:31.205557+02
12	app	0010_banktransaction_cancelled	2019-08-23 14:17:31.216874+02
13	app	0011_banktransaction_reimburses	2019-08-23 14:17:31.229537+02
14	app	0012_auto_20171212_1540	2019-08-23 14:17:31.240134+02
15	app	0013_remove_banktransaction_reimburses	2019-08-23 14:17:31.251251+02
16	contenttypes	0002_remove_content_type_name	2019-08-23 14:17:31.294872+02
17	auth	0002_alter_permission_name_max_length	2019-08-23 14:17:31.317717+02
18	auth	0003_alter_user_email_max_length	2019-08-23 14:17:31.350719+02
19	auth	0004_alter_user_username_opts	2019-08-23 14:17:31.377479+02
20	auth	0005_alter_user_last_login_null	2019-08-23 14:17:31.406114+02
21	auth	0006_require_contenttypes_0002	2019-08-23 14:17:31.418729+02
22	auth	0007_alter_validators_add_error_messages	2019-08-23 14:17:31.44356+02
23	auth	0008_alter_user_username_max_length	2019-08-23 14:17:31.518348+02
24	sessions	0001_initial	2019-08-23 14:17:31.707949+02
25	app	0001_squashed_0013_remove_banktransaction_reimburses	2019-08-23 14:17:31.723143+02
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x1f624f5ab12ec4a358cf1bb5e13576f65b232503d17234127ed6da35e73afef769772fa6fab3bebc90ecda2262a22cfad9a9cc8eb3e1f142dad8ea3d2e899703
\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xcacc4112e08fcde97d804d73c185df49f057b410ecd2501cac6adb4d19721211ba078605ec77f9e56e6b9a3551080ec4491b5bd6990727c1b54ea5b252402e04
\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xf9668ff67f89afe22d6e8cb4a2948ba9796328fe7858a9ce2f07f62867be69f10d3bcd14aded170897bd1a9ae103eb7455a50cfeb5412dbc52c802fb68666a05
\\x30e96d7ce24c879bf68e7a937fe081de7d33d63406e099d65520050821d9b6fa	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x6723cda0c1d74d33bb87894e71773f279934194ef86e694c48706e779acf5c8d3c9ec6447b07d809c6b03f0cc7e7d54ad8cf694f5eee6c321c5594e07c587407
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x8f8ffcf3b48c4121626cff3a20dde337dc6271549e35f55a9038db2289909d41	\\xf191f6470ce9ab2080a0801f6e53a31385d4626e89eaa1ab2ea6c1eef785ddb01567bcede43411c104844a288f7e18bec14bc75800e39febcdfff1ac33bf2113	\\x287369672d76616c200a2028727361200a2020287320234345384543393744434145344638324331414236323043454636313234454245383237413033303241393734463336433839433533354630454432434633424244363932443044373730353139414132343845414431464541304334383135354334393934413331344636443532363343393346463230343830423730313532303431414239344344354641353535363739333745344341373536434542313844453733334445364530354137303841423745323845463239333730344139383638363544373041373936423934353138363534414532384546364639383236374436353842454630463345434639334630304534384438413731413046463723290a2020290a20290a
\\x5b427d21ca80385b38a8c5d88d0e6abb269d15a9a8546d87a4908237c52d654a	\\x9e1af932e98982d1941c48ec4e1326a3bf4b7e68a35e6e266a2ed60ad51977e8e5f98ffa275503f73c5647e51c46493a7a31f140e93416416cd503ae64692ef5	\\x287369672d76616c200a2028727361200a2020287320234234454144383838424534413233393631444631313244333541363130333535303744454641453934364230324443333536383438333634334235454237333042413232463041463142384543304134463234443242384534363732374642373632334143413834463931353435303241303446343145313136453031424239343235363837383333373034383942314545464634383735313830364141363844373536453130353042313044313235414235354531463436463243434436463042334638314232313842423741303834453032313845323337413436374534424535433436413933363534413431343142333234374130363545423145464323290a2020290a20290a
\.


--
-- Data for Name: kyc_events; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.kyc_events (merchant_serial_id, amount_val, amount_frac, "timestamp") FROM stdin;
\.


--
-- Data for Name: kyc_merchants; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.kyc_merchants (merchant_serial_id, kyc_checked, payto_url, general_id) FROM stdin;
\.


--
-- Data for Name: membership; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.membership (channel_id, slave_id, did_join, announced_at, effective_since, group_generation) FROM stdin;
1	1	1	4	2	1
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid, last_session_id) FROM stdin;
2019.235.14.17.40-02TBK20CV5E48	\\x33f85ba6051b1884d68cdacb715c448c19ac07a0add265e67ee0f52c0741f972	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233352e31342e31372e34302d303254424b3230435635453438222c2274696d657374616d70223a222f446174652831353636353632363630292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636363439303630292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2236334d50545a3732394a335351584d45464139515a5234315653594b374e484d305647394b4e4a4e343032474738455350565830227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22344a5236314a454d38353150344b4732373635324a444634355631395832454b37595334563634395a5947433633465a3937413335424646543557514a5a50385838424d32334a4146474e535044474236504d514a4439473630545a5a304a4d564b3134374230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22364657355139473533434338394e4d43564235513251323448474354523158304e51393642534b595733544a523154315a355330222c226e6f6e6365223a22384a5950464848503756424a48354558534d4642435a39594b3756305344514748395a4345424b514351534d5156503831505430227d	\\xc7da1b6b9b7359c608d72f4d6ec393f0339af463c0c8476d6fb82e3f4593d7809dba9be4578480d5a057fbfebc206e5fdb1bb6eb432cc7745504d6eb44ea83a5	1566562660000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xc7da1b6b9b7359c608d72f4d6ec393f0339af463c0c8476d6fb82e3f4593d7809dba9be4578480d5a057fbfebc206e5fdb1bb6eb432cc7745504d6eb44ea83a5	\\x33f85ba6051b1884d68cdacb715c448c19ac07a0add265e67ee0f52c0741f972	\\x8f8ffcf3b48c4121626cff3a20dde337dc6271549e35f55a9038db2289909d41	http://localhost:8081/	3	0	0	0	0	0	0	1000000	\\xa5e94fa9ccaddcbec32c7920c7feb4910bfc22b1bfb6e823cd334c29af1f616b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2237443058593838534e44425944513641485145583135465053444551454643415432474d4e5232514646514a383945544d4e32424632475930474d4131335450565632444d59363533394d46304d4b475836424332533644413150595a46373348565332363252222c22707562223a224d514d4d5a4145434e5145425847534346344743465a4e4d4a34355a52384e485159564547385944364436324b42525a43354e47227d
\\xc7da1b6b9b7359c608d72f4d6ec393f0339af463c0c8476d6fb82e3f4593d7809dba9be4578480d5a057fbfebc206e5fdb1bb6eb432cc7745504d6eb44ea83a5	\\x33f85ba6051b1884d68cdacb715c448c19ac07a0add265e67ee0f52c0741f972	\\x5b427d21ca80385b38a8c5d88d0e6abb269d15a9a8546d87a4908237c52d654a	http://localhost:8081/	2	0	0	0	0	0	0	1000000	\\xa5e94fa9ccaddcbec32c7920c7feb4910bfc22b1bfb6e823cd334c29af1f616b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225448415952393859455034384639444732334642314450543641484a57475834584a3158535153374d4443513631593334523832315652534b54385a50485145544352564552544e5a5654454132504446364d3058564a53324346445a4238455037394e413352222c22707562223a224d514d4d5a4145434e5145425847534346344743465a4e4d4a34355a52384e485159564547385944364436324b42525a43354e47227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.235.14.17.40-02TBK20CV5E48	\\x33f85ba6051b1884d68cdacb715c448c19ac07a0add265e67ee0f52c0741f972	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233352e31342e31372e34302d303254424b3230435635453438222c2274696d657374616d70223a222f446174652831353636353632363630292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636363439303630292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2236334d50545a3732394a335351584d45464139515a5234315653594b374e484d305647394b4e4a4e343032474738455350565830227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22344a5236314a454d38353150344b4732373635324a444634355631395832454b37595334563634395a5947433633465a3937413335424646543557514a5a50385838424d32334a4146474e535044474236504d514a4439473630545a5a304a4d564b3134374230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22364657355139473533434338394e4d43564235513251323448474354523158304e51393642534b595733544a523154315a355330227d	1566562660000000
\.


--
-- Data for Name: merchant_proofs; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_proofs (exchange_url, wtid, execution_time, signkey_pub, proof) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_refunds (rtransaction_id, merchant_pub, h_contract_terms, coin_pub, reason, refund_amount_val, refund_amount_frac, refund_fee_val, refund_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tip_pickups (tip_id, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_credits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tip_reserve_credits (reserve_priv, credit_uuid, "timestamp", amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tip_reserves (reserve_priv, expiration, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tips (reserve_priv, tip_id, exchange_url, justification, "timestamp", amount_val, amount_frac, left_val, left_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_transfers (h_contract_terms, coin_pub, wtid) FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.messages (channel_id, hop_counter, signature, purpose, fragment_id, fragment_offset, message_id, group_generation, multicast_flags, psycstore_flags, data) FROM stdin;
\.


--
-- Data for Name: payback; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.payback (payback_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: payback_refresh; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.payback_refresh (payback_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xb772a719c7243baf10ff4e2d0d4c9d8ae0845fb907b76c609c6fb8bcfdfe2f51	payto://x-taler-bank/localhost:8082/9	0	0	1568981859000000	1787314660000000
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_close (close_uuid, reserve_pub, execution_date, wtid, receiver_account, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_in (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, sender_account_details, exchange_account_section, execution_date) FROM stdin;
1	\\xb772a719c7243baf10ff4e2d0d4c9d8ae0845fb907b76c609c6fb8bcfdfe2f51	\\x0000000000000003	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1566562659000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xf4c83092ff94ded9d4e42e7d56335be7b6718a9b96ffb27b29e5606f235a4d63d4dba07909b24e2a1de1a5ad59996442c516682da356f122a7e26bebfd2e0898	\\xf191f6470ce9ab2080a0801f6e53a31385d4626e89eaa1ab2ea6c1eef785ddb01567bcede43411c104844a288f7e18bec14bc75800e39febcdfff1ac33bf2113	\\x287369672d76616c200a2028727361200a2020287320233843314443354644343542463042394146424535444538314539313632413236433945373331373242443143313342373143383434344438424334443345443638424630423342434234423535303146374139323444303746383732463739413836353038323139383546464243334431313033363742413943353132424642433734413844303643323345463341464534303441413835433541413531434434434633343438393536413632394236443831343235383545313734383546343033303946444634463141383539353231383141374436373946423446383530363639373437393830383242374545393943423231444630424137303546353423290a2020290a20290a	\\xb772a719c7243baf10ff4e2d0d4c9d8ae0845fb907b76c609c6fb8bcfdfe2f51	\\x82cd283efecf1d85aa2b813615091f97e507a162d0757de473d896da92ac6d6b2cdc1e9463f248a72a3b16e2f0ca92c3a9a68c5e1d9fc18490d338b3df661104	1566562659000000	8	0
2	\\xc9579cd081c16d5a23893e55b55c9ba9ea4b8bc00ff3407532bf1305646d757007b1d56a3045d120c74c2d4081930f1fb495704c51d5e87fe4f887ceee7592e9	\\x9e1af932e98982d1941c48ec4e1326a3bf4b7e68a35e6e266a2ed60ad51977e8e5f98ffa275503f73c5647e51c46493a7a31f140e93416416cd503ae64692ef5	\\x287369672d76616c200a2028727361200a2020287320233439384134334339393233464434384437424443453839443046343545424234384338383838454646413134384243434241393346383435433935334637304342434632353832444630363033333638434633463838313145463837354235373837334546324545373843373134343038433037463841384339433432353938453934383934384634434537323843333937373135433146334132353745343444313042304439344339453630463544444646393135413644334541384536433036434130453743454342393039443334304136453232363741444541383535303741353130394542433646463042324645303130314439334332444436454223290a2020290a20290a	\\xb772a719c7243baf10ff4e2d0d4c9d8ae0845fb907b76c609c6fb8bcfdfe2f51	\\xe0661792511b372e62d73213b4b3bda4e4f61bec73174c2c0d5e1114c9baff09042e5c58de873ebd93375d4c8740cdcd7ca1b55baf48a5d6bb9d535067322501	1566562660000000	2	0
\.


--
-- Data for Name: slaves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.slaves (id, pub_key) FROM stdin;
1	\\xab65d6c0ddaa77d3b1d90d83fcdf86918da7339c92fb502fc718e39bbb7c873d
\.


--
-- Data for Name: state; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.state (channel_id, name, value_current, value_signed) FROM stdin;
\.


--
-- Data for Name: state_sync; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.state_sync (channel_id, name, value) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_auditor_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, last_timestamp, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_fee (wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_out (wireout_uuid, execution_date, wtid_raw, wire_target, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 9, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 3, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 1, false);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 1, false);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 21, true);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_user_groups_id_seq', 1, false);


--
-- Name: auth_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_user_id_seq', 9, true);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);


--
-- Name: channels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.channels_id_seq', 1, true);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 2, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 7, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 25, true);


--
-- Name: kyc_events_merchant_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.kyc_events_merchant_serial_id_seq', 1, false);


--
-- Name: kyc_merchants_merchant_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.kyc_merchants_merchant_serial_id_seq', 1, false);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 1, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, false);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.payback_payback_uuid_seq', 1, false);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.payback_refresh_payback_refresh_uuid_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, false);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 1, false);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 2, true);


--
-- Name: slaves_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.slaves_id_seq', 1, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: aggregation_tracking aggregation_tracking_aggregation_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: app_bankaccount app_bankaccount_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_pkey PRIMARY KEY (account_no);


--
-- Name: app_bankaccount app_bankaccount_user_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_key UNIQUE (user_id);


--
-- Name: app_banktransaction app_banktransaction_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_pkey PRIMARY KEY (id);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_denominations auditor_denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denominations
    ADD CONSTRAINT auditor_denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_exchanges auditor_exchanges_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_exchanges
    ADD CONSTRAINT auditor_exchanges_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_historic_denomination_revenue auditor_historic_denomination_revenue_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT auditor_historic_denomination_revenue_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_user_id_group_id_94350c0c_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq UNIQUE (user_id, group_id);


--
-- Name: auth_user auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_permission_id_14a6b632_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq UNIQUE (user_id, permission_id);


--
-- Name: auth_user auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: channels channels_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (id);


--
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: deposit_confirmations deposit_confirmations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_pkey PRIMARY KEY (h_contract_terms, h_wire, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig);


--
-- Name: deposit_confirmations deposit_confirmations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_serial_id_key UNIQUE (serial_id);


--
-- Name: deposits deposits_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: exchange_wire_fees exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.exchange_wire_fees
    ADD CONSTRAINT exchange_wire_fees_pkey PRIMARY KEY (exchange_pub, h_wire_method, start_date, end_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: kyc_merchants kyc_merchants_payto_url_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_merchants
    ADD CONSTRAINT kyc_merchants_payto_url_key UNIQUE (payto_url);


--
-- Name: kyc_merchants kyc_merchants_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_merchants
    ADD CONSTRAINT kyc_merchants_pkey PRIMARY KEY (merchant_serial_id);


--
-- Name: merchant_contract_terms merchant_contract_terms_h_contract_terms_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_h_contract_terms_merchant_pub_key UNIQUE (h_contract_terms, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_row_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_row_id_key UNIQUE (row_id);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_proofs merchant_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_proofs
    ADD CONSTRAINT merchant_proofs_pkey PRIMARY KEY (wtid, exchange_url);


--
-- Name: merchant_refunds merchant_refunds_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_rtransaction_id_key UNIQUE (rtransaction_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_id);


--
-- Name: merchant_tip_reserve_credits merchant_tip_reserve_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_reserve_credits
    ADD CONSTRAINT merchant_tip_reserve_credits_pkey PRIMARY KEY (credit_uuid);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_priv);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_id);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: messages messages_channel_id_message_id_fragment_offset_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_channel_id_message_id_fragment_offset_key UNIQUE (channel_id, message_id, fragment_offset);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (channel_id, fragment_id);


--
-- Name: payback payback_payback_uuid_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_payback_uuid_key UNIQUE (payback_uuid);


--
-- Name: payback_refresh payback_refresh_payback_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_payback_refresh_uuid_key UNIQUE (payback_refresh_uuid);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: refresh_commitments refresh_commitments_melt_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_h_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, newcoin_index);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (rc);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (coin_pub, merchant_pub, h_contract_terms, rtransaction_id);


--
-- Name: refunds refunds_refund_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close reserves_close_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub, wire_reference);


--
-- Name: reserves_in reserves_in_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_pkey PRIMARY KEY (h_blind_ev);


--
-- Name: reserves_out reserves_out_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: slaves slaves_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.slaves
    ADD CONSTRAINT slaves_pkey PRIMARY KEY (id);


--
-- Name: state state_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state
    ADD CONSTRAINT state_pkey PRIMARY KEY (channel_id, name);


--
-- Name: state_sync state_sync_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state_sync
    ADD CONSTRAINT state_sync_pkey PRIMARY KEY (channel_id, name);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_out wire_out_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: aggregation_tracking_wtid_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX aggregation_tracking_wtid_index ON public.aggregation_tracking USING btree (wtid_raw);


--
-- Name: app_banktransaction_credit_account_id_a8ba05ac; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_banktransaction_credit_account_id_a8ba05ac ON public.app_banktransaction USING btree (credit_account_id);


--
-- Name: app_banktransaction_date_f72bcad6; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_banktransaction_date_f72bcad6 ON public.app_banktransaction USING btree (date);


--
-- Name: app_banktransaction_debit_account_id_5b1f7528; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_banktransaction_debit_account_id_5b1f7528 ON public.app_banktransaction USING btree (debit_account_id);


--
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON public.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_reserves_by_reserve_pub ON public.auditor_reserves USING btree (reserve_pub);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_group_id_97559544; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_groups_group_id_97559544 ON public.auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_user_id_6a12ed8b; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_groups_user_id_6a12ed8b ON public.auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_permission_id_1fbb5f2c; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_user_permissions_permission_id_1fbb5f2c ON public.auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_user_id_a95ead1b; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_user_permissions_user_id_a95ead1b ON public.auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_6821ab7c_like; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_username_6821ab7c_like ON public.auth_user USING btree (username varchar_pattern_ops);


--
-- Name: channel_pub_key_idx; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE UNIQUE INDEX channel_pub_key_idx ON public.channels USING btree (pub_key);


--
-- Name: denominations_expire_legal_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX denominations_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_coin_pub_merchant_contract_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX deposits_coin_pub_merchant_contract_index ON public.deposits USING btree (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX deposits_iterate_matching ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: history_ledger_by_master_pub_and_time; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX history_ledger_by_master_pub_and_time ON public.auditor_historic_ledger USING btree (master_pub, "timestamp");


--
-- Name: idx_membership_channel_id_slave_id; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX idx_membership_channel_id_slave_id ON public.membership USING btree (channel_id, slave_id);


--
-- Name: known_coins_by_denomination; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denom_pub_hash);


--
-- Name: kyc_events_timestamp; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX kyc_events_timestamp ON public.kyc_events USING btree ("timestamp");


--
-- Name: kyc_merchants_payto_url; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX kyc_merchants_payto_url ON public.kyc_merchants USING btree (payto_url);


--
-- Name: merchant_transfers_by_coin; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX merchant_transfers_by_coin ON public.merchant_transfers USING btree (h_contract_terms, coin_pub);


--
-- Name: merchant_transfers_by_wtid; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX merchant_transfers_by_wtid ON public.merchant_transfers USING btree (wtid);


--
-- Name: payback_by_coin_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_by_coin_index ON public.payback USING btree (coin_pub);


--
-- Name: payback_by_h_blind_ev; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_by_h_blind_ev ON public.payback USING btree (h_blind_ev);


--
-- Name: payback_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_refresh_by_coin_index ON public.payback_refresh USING btree (coin_pub);


--
-- Name: payback_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_refresh_by_h_blind_ev ON public.payback_refresh USING btree (h_blind_ev);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


--
-- Name: refresh_commitments_old_coin_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refresh_commitments_old_coin_pub_index ON public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_coin_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refresh_revealed_coins_coin_pub_index ON public.refresh_revealed_coins USING btree (denom_pub_hash);


--
-- Name: refresh_transfer_keys_coin_tpub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refresh_transfer_keys_coin_tpub ON public.refresh_transfer_keys USING btree (rc, transfer_pub);


--
-- Name: refunds_coin_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refunds_coin_pub_index ON public.refunds USING btree (coin_pub);


--
-- Name: reserves_close_by_reserve; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_close_by_reserve ON public.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_expiration_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_expiration_index ON public.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: reserves_in_exchange_account_serial; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_in_exchange_account_serial ON public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_execution_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_in_execution_index ON public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_reserve_pub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_in_reserve_pub ON public.reserves_in USING btree (reserve_pub);


--
-- Name: reserves_out_execution_date; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_out_execution_date ON public.reserves_out USING btree (execution_date);


--
-- Name: reserves_out_for_get_withdraw_info; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_out_for_get_withdraw_info ON public.reserves_out USING btree (denom_pub_hash, h_blind_ev);


--
-- Name: reserves_out_reserve_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_out_reserve_pub_index ON public.reserves_out USING btree (reserve_pub);


--
-- Name: reserves_reserve_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_reserve_pub_index ON public.reserves USING btree (reserve_pub);


--
-- Name: slaves_pub_key_idx; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE UNIQUE INDEX slaves_pub_key_idx ON public.slaves USING btree (pub_key);


--
-- Name: wire_fee_gc_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX wire_fee_gc_index ON public.wire_fee USING btree (end_date);


--
-- Name: aggregation_tracking aggregation_tracking_deposit_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_deposit_serial_id_fkey FOREIGN KEY (deposit_serial_id) REFERENCES public.deposits(deposit_serial_id) ON DELETE CASCADE;


--
-- Name: app_bankaccount app_bankaccount_user_id_2722a34f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_2722a34f_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka FOREIGN KEY (credit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_debit_account_id_5b1f7528_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_debit_account_id_5b1f7528_fk_app_banka FOREIGN KEY (debit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auditor_denomination_pending auditor_denomination_pending_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.auditor_denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: denomination_revocations denomination_revocations_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: deposits deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: kyc_events kyc_events_merchant_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_events
    ADD CONSTRAINT kyc_events_merchant_serial_id_fkey FOREIGN KEY (merchant_serial_id) REFERENCES public.kyc_merchants(merchant_serial_id) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_denominations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denominations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_reserve master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_aggregation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_deposit_confirmation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_coin master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserves master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserve_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserve_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_wire_fee_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_wire_fee_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_balance_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_balance_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_denomination_revenue master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_reserve_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_reserve_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: deposit_confirmations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_ledger master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_ledger
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: membership membership_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.membership
    ADD CONSTRAINT membership_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: membership membership_slave_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.membership
    ADD CONSTRAINT membership_slave_id_fkey FOREIGN KEY (slave_id) REFERENCES public.slaves(id);


--
-- Name: merchant_deposits merchant_deposits_h_contract_terms_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_id_fkey FOREIGN KEY (tip_id) REFERENCES public.merchant_tips(tip_id) ON DELETE CASCADE;


--
-- Name: messages messages_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: payback payback_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback payback_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: payback_refresh payback_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback_refresh payback_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_coin_pub_fkey FOREIGN KEY (old_coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refunds refunds_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash);


--
-- Name: reserves_out reserves_out_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: state state_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state
    ADD CONSTRAINT state_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: state_sync state_sync_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state_sync
    ADD CONSTRAINT state_sync_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

