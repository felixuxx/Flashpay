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
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bytea,
    wire_out_off bytea
);


ALTER TABLE public.wire_auditor_account_progress OWNER TO grothoff;

--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
    last_timestamp bigint NOT NULL
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
1	Benevolent donation for 'Survey'	2019-08-24 22:54:18.888962+02	8	1	TESTKUDOS:10000000.00	f
2	Joining bonus	2019-08-24 22:54:22.811489+02	9	1	TESTKUDOS:100.00	f
3	83AE3CTH2KF60Z0WYBGWS8GXGGV2ZASEBHT77XBKQXB470CQ5ERG	2019-08-24 22:54:22.952633+02	2	9	TESTKUDOS:10.00	f
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
\\x2d55235219a1e605ab4ed74ae1de9a893658ce124f15a84bb50c6e80f49a6095fe016543ed02b57d1f4c4ed9688853c21a70c7e003714fd5f1b7bcad01631950	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3299a46c38e53942eec65da02437857c5de048e46c7cd2506b9df54b067044f4b68c7799d61b4f68a3832871fc9ef153d65d8a439a72c51713d7a3f5a905c148	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0217ab3b057d92de202aaff6489865de103a2875bf8bb208e3827e75da74dbdd7331033db0252dfece52e211d301d763139f14e32926114f5a4be3d4b59e2e55	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f39418d1aea8abd8b19fdda8e8453181221d585dd178c5aadad4ecfa44bcaec439b2dd9c57abee93e7ce6f501c0314a233de5c3b08f60f1b4892f7cf987225f	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e3be4dfd1a856c119b06e080ab8e7d5334ef8c602dc419ae7b061f7a740e02763a17b5421939caaf46d610154121acafee4a978433ce958432cce2d7166590a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x63e700cdef72c9d4684e21b5541e6a93eab1a5bcf1321f0f84f734c95d503619dac77767036b56aba8c48c8fc0c94284e8cac6f66f6a00fd6f81313e32747626	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x825518a723ef7b11a9d498f3c9462812d945cea66bcff38e6256e688f98544f054552910d1aa980e307d272f3188981cc8c01f5b2c96792203912e4bc25926b8	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2254f63c89e5ee00a4860f27feea62b24e9a9459480e437c97fb049dfce555486c009bdb41a7e284c3023d0ffd5c4d899a3eae8474e1f5e7e9ba116b6e7b9466	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x07d3b33eac0c7e4a181d3a51605bf63becbaa1af36631840586aa1df2ccbaa781c044f52cd46fb0ab4abec7cc9f505dcebf5ae18cd8ad74926c2cbccef062fce	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa351471cfa41235d04bcb079ac4106801e41f8b5a031a300e5e16f073c6c2ec4fba4d423b24feaf26be358db1d6440e79e77c7e57030e93c9f11679ca9012633	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x47a5db061766ea239c70e8efb63be1083cd32eb40132dec995cb07396a5c50b389eabc062fbf2560f6e6f59a801203911ad3293774a99f564ba6f48cbf8cc45f	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x551ba97f78c5bb52cce4fa82df7c84c36ad17875a71a4f5f30cecd11f84eda8704cd4033f81630240c72dc6a85fdf0f44f30762e5ffd9d99e4cc692f17af096c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb613df23104dad23e5503d79fba0e45dcb8f05e76cdfa9379913ba69c33d22966a25eb31e602da93cf83d1633ffed57a492628dba4b0ea3dd89565ebe87d1a0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc8c41eaf46c847798f1addae8deea61a2ba7850e774e17e3baf21f0b49f07bb429b0cc84780f43a031a48c3c549aa706b4f0a19070a5c55d5955d1346681b76	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf67558241771e7c25d83a587bff241208910280bbf790b2184d2b2669aadc410351f057521511719f076abfb589d614935c7ab74517296f1391a752bd676dabe	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4efa39927611a913e5306d2e54f3872aac1db37e188cb9f9427b79a89c5d4f341b05ff91bc3601cd7c279c10efc1a0e61ed5d12f03cc8732615749cde2e76bf3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b54f1d1d432c0bb38326b8afd799f4706fbdce77888dcb63d7ef0be0fbea59940ff9049db7542d023c02a78bbb9ff0a6d47b4b46b6b0ebfbc94e4a838015050	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x109f2a7cfbe4117527eff168631dd2d5791b9c84cb2679e1bdd915588b998b3e6d9edc169625286178eb827f9e51fea1acad706c337f64e65216378c4678cf9f	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86444c7d6c95615cb59088e0b24c67f4201e40db098e324f44c597aae9099261665338e40d1af14a2d69c016f0ece252dced3f56746f26d744699a90252c9f18	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbaafe94a16f6acbbb81c0a4cb246581cbb7b9bcbde397bfcc3c0974291768a2b385eecab606c46e7f527f5762bf64d5aefc95f6196ee16ad95a8893641256cb1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18e6e71cf04a43ee0a71dabed6ae4c8913c6ca02ef5bf940083941e3b3920d9928942db1db054755e8933c1971c49f3f2e6bb767e9d9cf305ce8466621c4dedd	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd719c1a1098e7fbcd25039e03b1df6f8a4652810b3967b0c518f28a327dc9e9e27e3c47b73763de8223eea222e341c2e60d11d1849f8ac7e633088a58f6c33b3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a6e70205bbc541f9c4b312289e084e6c6bf92579b87a741fe90cf83893c0bcb9cf119a5708f216beea8928b4c02daaee1f6a36edd67ee189da9ae4f9272284b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7ab0263901c24f5e000fd03cd52bea6d8ce031d383591037983cd9128317f4519b11314cf05222bc2ae7fae486bbb08cc2354a463354690cde080e152ab964f	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1792924dd43c1e4f6f26322cd93b325e637aa0a593e84c94aa280860557050c7c8696a0e078ed8949225c5be5eef7782cc7d87223f95ae1f2708be7551f3e6c3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a3599206223b36b342695e3b26cd73335b5d8bd0a1eb1b2ef63611976d0d2aea270fb357762e41f4f4085d127a95472db1db40b7ab856a7b1d2c427ffa9af64	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe50e658150bd735c791434e4079504f3c54206c8c8eb9f461ecbfae98e1b41d9ada1be629ee39bdde6b3f5d35128bd1bc95ab7a4d5bd66e79bd39bcfe9fabfb0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2508c6595fc61aa37b4eb61a700b5c88b663f09ac645e302f6a2839b29c060ce268ab1554965b6aee7a3c4a57b013a89a3bb00001e126fdbceac0b8248d26545	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8282911d367c04c3385d24fb828b0ef76e9a264ba74ae3d596f5efecc346c1b6d29e8f749dcfcc1f161b2f7be7fb887bc5d71f4e8d58768a39953c4c4dc2283	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33b552adea34035c7627a14411fa43b3f60abc59f6ae9e5bba33802a87d3dbff76e0aa78787a5988bf8fb158cda8175ee17e4155f6a161aa058797b994d6b4e5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x538f030c8b49ca07c19f89af39962b7ed06ef9c2f528c6e6892c4cc9442f427ca27424a70ab7a68854268109873896a88cd4789cb99b1d235ddca052f2f73abf	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd00c0b7f6d084ef073c0f8194a41b8377cda5bbdf3950a209538d8f5b6753aa1db84cd3f106b3e94e52e14e2409649cf488222cb6d2a609b4cd443354d5cbb51	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a398932de520ae006fb8aa6c6571d42df29aeba4eef47d75583478d08e7caf5549af062e6307ba0aa0d3a4faeafe9e808eb5e7e494bebe3b0282527da22b3e4	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1143dce93317f2e1526feef87fbbc95a748df208a2078ca3ec55743a782d63e36456538d89ab84f097b6bde0cca9835e0c8f4aeb2658fe8b0d713473f806e688	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	8	0	0	0	0	0	0	0	0	0
\\x960fc30cd57ca7bfe62fa23a95a89f4901be052795ece5c137da068e67dfa67e51920885a72ae7f72799840d0118c46f75f974d4bce93a1a6e98b2b403696e12	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	8	0	0	0	0	0	0	0	0	0
\\x7a0dc43e5c08b71876cae99c17373fabb225f678af8d7ae121e1f6c57eb7bbf15fe46eab1fd9e9baff5aafcf68cc59661ff62a4b8aa684404a45c3f8c6f91d8b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	8	0	0	0	0	0	0	0	0	0
\\x015c82cf76ed65cfda03774f6d04e6011e305987112e3b03610614a2e976629df060c16180d605d538d20c0b70c9af9a9e857cd8d9121f9941011784715d1eed	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	8	0	0	0	0	0	0	0	0	0
\\xdcd8f983a92db54f2291b728d4e6ff7ae1916bd94255a240509bc98409c6e3e5e127c8e69645be261a17c28a4073540dbee632d1f17118ebe4bb23ee122f4128	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	8	0	0	0	0	0	0	0	0	0
\\x8d4f41439498f8d8323b6deb95921e39dcd0f3c3f1d0afd35cb3e79aa03aa74ef9abb9d51078294945e586e377aefffe158db28e053a0e1c6f860677c012fb34	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	8	0	0	0	0	0	0	0	0	0
\\x1a7a80c0c60eb8bf716018c1eaa23545b0f9623997ffcaf1b72ec2b5826ac23be19188eabd8b62ef8e730038effd7c151501ac83c8d9d4343044b957d116a5aa	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	8	0	0	0	0	0	0	0	0	0
\\x40965d686d70cbffd3bfb70d1f2d55660eba14a268541a3ad3ee561cd2c6564847dba690bfb68285129f9a2eaf396776790eb7894c6c0f0cd6d95b767f4a3009	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	8	0	0	0	0	0	0	0	0	0
\\x4dae7718307affbc671efbf89a601e242b943fe206728039b884432e2d763c07677ae0478385398f3e0550980535731a36804bb9af6a786de91d407ebc04e667	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	8	0	0	0	0	0	0	0	0	0
\\x8e4405d5e413455864067e309fcc01ad11a5e64336209cb4bc31c0acc3916a5dd0b996028f4366b78d4b788063c7db1a9773a24f66c7912cc8da7e99ecedb58a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	8	0	0	0	0	0	0	0	0	0
\\x184aca251ed1a0f512cf959d6f88e8fae5e2582572532120eead2b08f388b00af8d78aafb993846b311ef32ee098ee345011c306dac049bf85ad3e5d3c19deeb	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	8	0	0	0	0	0	0	0	0	0
\\x2ad6a5ac3baeeb22d0566f8a40d41d5d3462c64d84a8f94eafe1626f20c6dbe488661ae14170f13e7245d01cb7c807baf62ffe16a09d479623340e98596d6188	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	8	0	0	0	0	0	0	0	0	0
\\xc3fb16e1826e3e480a271f36434a0b918236be6faa13f7ef960620446f1ffd1022c0776fbcd564c378a717a767231761a322e5975d6f2134484ed4b5f4327965	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	8	0	0	0	0	0	0	0	0	0
\\x9c2f1b5681316176447771b67982fa69a29c7a8665c66c654dfea88727127a1570aa421fbe028fccae79bba14995e2583c3f76a7a76e97cde846f1da7bbcd0cf	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	8	0	0	0	0	0	0	0	0	0
\\xecc06d87f5293989e3f451f14ef65c6f6a81a97f3828d042bf55a7ab806b8c45f04a49ab5378e39ca92a58caa0d498e7bc8270bde8397f04f8db68a305d9c471	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	8	0	0	0	0	0	0	0	0	0
\\xaf4215d06be6f7f4b3ec88a80b8c868a64ff3c8b57583b8b663d079f44638bf5bc1341d69219ccbe46ee9bf3d4baaafd0ddfb416a8bd6adabc76fd54bed22548	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	8	0	0	0	0	0	0	0	0	0
\\x4b9a8a9a4a0ec1acec8327332dfc678f652565459658d8d885598e72852aec2f5fc946b5b141c844b0a06d86d56e5421c2def428ccf335e9e62681a4134f4dd3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	8	0	0	0	0	0	0	0	0	0
\\x826e4820c40bde6b3defca3e179f6895242aab5b1d97af37a9588b3155669c742f61c02d3a8ad94a9f8be3c9ab402ef0a9db89a0fa4ffa4c24a6a7760c27c12e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	8	0	0	0	0	0	0	0	0	0
\\x0f22e374575348a5acc346bc045fbe272ea168f3b5ccb2214056c736a404115dccfa6811e285c1985a8e9f449e2a3b8d9fb52307c80571bde722b4d0da83c3d0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	8	0	0	0	0	0	0	0	0	0
\\x16d6ab392f8991bd5803cf2b650be69c71a6f992e4ee0df89546eea07f2e3633cb8a9745c118071bd7a7714a05e693048f53e7670b9f7557f3c22ab12eed9261	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	8	0	0	0	0	0	0	0	0	0
\\xba7073338de81f5e20ce36e24f4713f62128ebdb7ec1767215961b096fb8f02fc93a1e255078971648e023fe14b0978b5b0587a4abc0a7da7cd6012f65597c33	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	8	0	0	0	0	0	0	0	0	0
\\x791f3270f031db35d40d49f026df97aab2a62f1cd68da8ddc982f41941d8715370f09d6c73f46b7a3da09ef97aacc799397ff6469d1868787e477fcc1fbb6d92	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	8	0	0	0	0	0	0	0	0	0
\\x1288ff0d182b3fe885f4ab0f556105eaaf23bc6c6ffed4a3ab0744a29c70c359d7c16b3aeba4e49d53c3a59c62c99a10ba3ef9ad72215bfa910dbbde0f2d0a36	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	8	0	0	0	0	0	0	0	0	0
\\x2875c50f8fa0992bc58cfb89dd2f4e3a1db7002bf626b99d81a6c045b6d2f1e982f7a55dc3d7f55841fb799dea37f22027e3d3a06ad6d06358cfa814e76a6e36	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	8	0	0	0	0	0	0	0	0	0
\\xf4ddeed1724171081da315f8f390faddd8747856e1d57bedd1a2ed785af3be908b4a7500d8e41e3bae2cf83318606f491267c1f9b9d0e7e8e582540481a96059	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	8	0	0	0	0	0	0	0	0	0
\\x702330055261d3f39591d627ce0a4db38eff308627b58d24cf7e1e4643b3ece9fc794bfc92bc5f708b7b73b5cc76979b8771c347b7bae13b653432bdbd0f79e2	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	8	0	0	0	0	0	0	0	0	0
\\x5584092d439add6b8868e8cf70ea8a074cce5b6524f6ba50150bb58903c85fe0da6a37e24ce741f543daa8ce9486755ccd7b0211e52902a41528b3dfbc9b3a23	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	8	0	0	0	0	0	0	0	0	0
\\x239ff048944d1b3d29e14b025be021f0b3396835f996d03ef6a0c863e33ab23d682cd5c44e09d8e916ffe7d277c414cd4c5df54b12b726772dc3676fe3231d69	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	8	0	0	0	0	0	0	0	0	0
\\x408c43f4ea2e0a0d4abae5c9499311180ba71edc0f220a2a2c0c605008c8384524a085ab709347e5914793c4488a5d48397c346f6d468248d3b40189680eaefd	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	8	0	0	0	0	0	0	0	0	0
\\xb38f6a55e23c9fd64a8e135adf758535fd001aedd851214ef148e4a2f26418679954046ff20c0dd7a6091be238f783d59aa6079233156f19f8b8642b4ede6ff2	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	8	0	0	0	0	0	0	0	0	0
\\xb4f0a316b06ee1fbe02cbb38cd6fa5e8215d15e060f186b55a10bb7b72dfed95d51c1471426de8b4948fec6ac923904409cef655e11d0c8edbcc5ff5a319e471	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	8	0	0	0	0	0	0	0	0	0
\\x6b1ee9a75387bd24b3999e51811dab98d7cd82fc53a74f08bf03f5c3f06b7d7878cccff49d06762ed86d1fba356cfc21e75c8646290e2d8db720f484b0b2ab69	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	8	0	0	0	0	0	0	0	0	0
\\xef4b8cd26e05a7db353dddbf5e186979ae70308d486e569abcff5868d3d352ab12768623c5472fa5ead3918c61fcdbf183857c621f5a45a7dbe9675caa4afa01	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	8	0	0	0	0	0	0	0	0	0
\\x9ed70846bf1d5e7e449f7ccd6faec8e5b52a42b1e7932f070602daf016540773a753e5bf7d155ccad3b42abb53941e59a65838f6e872e38547239bc9afcc0d3e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3bf7ab33c6ff5d65846d03d447a0233d7196cd85738b0d94f466f060404cad46e991fa84fbadc16488d64b758e5bb5f56dc47a50fb7c203a6150dffc20cde427	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79bc9d8d477fbe41ee5ea89449c897392c4fd51a07a06c41a2d77e8c8442d768cb1f4f787943ba30b3b78b669621953b24309201a86dbc17856a91e2f3dc32e0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b7abddcff03f823f8e0c91f06ec48406fbb72f9f2decb89f12cc128f03f0f6e5facbb62aa9bfd909125dbf643db7cfe14ac7dbbe95afbf6158d19c740e51ec9	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb02330403a8038129442ab0b420453b5ac3d3e37154e11705920fb554cafe14fec96aa93b2dd85cca39e46691250f815ccf9f426dbfb4b3c11b283cc92ff8f55	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x54bf18bde43266188a67533edb5fff71ec72c6ec265ad0e37a8339711fa67868b1a0e1691c758f1a1f7ddd9a8d3ef4565b614ac0e5eae06e6c5a853ba3dab9eb	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2985964b0d43c5d8310c55bcf2423803f48154673b387f3d5d9bfdad03e1a2ab1fde61abbf368cbe3644d52e8189eac86bd3626df59d3828db01308c5dbe91c3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e3399a8feec589c06f8f809e29a3a895de2a08a462758d16216e8270ad18ddcd9665a72e49576439e090ce4f316df4688f3d1c9c599d65cb3f86babac535a69	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x15b2cccea95a5a8e571e0384b7f7b32bd3d113dfbacaa90b80009d471d586a776027742a8341507a247195570623b5c2827286dc7fad1704e6d29e67d35c80be	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x21cf9af35e6e4507101ddf2188b8028fe3e12930d33078f610e5125b91c4968256a375e3530e481419a0a45012ce24408c6f94ab536d30b0ec1c460ec940657d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc205c501f1018c0e87b392a455e3343cf572e3749161a52fd5c8111565c775d6c0ba8cec858706e2bf4b031ee2474eb03855ef61ceb1e6721c5f4dbbc5c12576	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe32e4e63bb797ecc140eb02010c516a16c3f3a0b7b7f9bac93aa8068cff10c1e22b116e186a9f4bd209bb219d847dbb8e2ff1abba7abec25d906b05a3160856b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb18b1872d606b52897e273d9ef2d8fb06423b32c7a3615fc07bd47770072ab7e93e4cac8a51ef1a3afb82c5e77e23d21728f20e7f3c2defc38e24f215568cb18	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x278869e873e3d7ffce840f757cabac3da7ec6d2c0079e31ce988e046845535b4ef98f9720716e90b08739fdf79e4fcbc302d56f0213d634cef87b30e97a9c0bb	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9e1595c83054af142f2f326670b83c3e4afb7f0d7ae2e95975bfd8abf5796d1970b88241207fae4f12836f00081761aad0ae327f4074e567e5589e65310ba49	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5de51a1cca56511fb89d7dfe6d4469f4f495a1e8a86ab21b0362a0e4f0e70f4df71bee879681dc441f4edc5284b1a5ec76a3adcdd893e4370fbb660940414869	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0dbee75db2e12beadeca94b421114fa96ea3ebae0edc2bba51581a955a6f5fca6e4d586fd617c17f80fcb156188c46b0aab46c376d6968721efd9de449db7890	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x762cc9b1e75667f93b260a11b94ab0c8c033b47b353b2c9a3a2e013a86444580f4fcabea4e603b2975330d8b9e6fd061091ffac06f332cc748387d66925f6721	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x56c8ede9838208e5f4c7aea042cdbb9152204e31e641832c4128921042b1c058ecd1c27007ceee4f7023a1b307b7949cfce9bf4467b7c4c77b71b21461de1d0e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ec120ed7ef241e2fec6e1836d0d4d65c0d63aa693c5ee3acca0be9497d6fc80d861b8301b6a4d4c0a629d52d351ef7d7284657a079f87f316c0f5374f19d5eb	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3dd5eda9c45e0963eacd6921a206c63d4dd237d02d29b20bc61eb078533132090bbb6f6d11cc6d8b2f85e2a6773ea2ac8db217b7f75a7cb192e534d7bfb9851	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x035f0c9d18ee504d47c91470055d01fb0f7e039c2acd9b615cea7ef7b3fe0f2a8cebe1d7f42d167cd458fd7bdb889598eaa3b33b033b58f8545a4068ab73f5bf	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f1313fc822de9b7e08be79a7211c469e214bf28c3292cec49716639c10a846e201d58d8cf396250724ee7db4e55db8f7159f6607ae7f3cf444a6000ae6f8b6c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2535684dd8f0fecfb30cbded360357162fa327877de9b14a23b68dae2d78ee4b721b4ed75552d570a5077479afd11eb0fc8cef90ef3289984cd4fe0d1a945e28	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9100871375ffc2e691d03dd55a533042011f092e4630d9c119bd012a168824139e483bfc554bb09b1010b4cd2379f59b1c1975100c033f15e4b7ef3402d6535	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5d90c137c26a9482f306ce42e9f0ea416e5f1f3b01ca9bc7b70e3d6b1e9ebb4542c56e65233a7a90073d494059eb5ebce1517143ff0c10c88b9580ff48cf60b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x07a2bfd89be1039785a0f6a0b3186457a2a318709346a3fb3a6d0beb02185ce83d5093cf1e98197b0ca8e02b704c23914b4500d01d4466c4645f792a5a4743d3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d26631783f5b2cdf0773b03128a0688accb28b2b4fd3ec6e9116727521c3a44c4f554022662d2d279082d3c0aaaef2d1a438e3ea13bb18d16b42b9583587a56	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x493f8b6b55f6fd675945ac0bdc0ff344e1115a1c8efc50b5feb1270dae0bf67bbe6abedab24f7443f421dc95e7b654969a9ff159c6e5b69a266995e9c75bb99f	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x46dea1a1b534ff97ecd7c7bd69e79affccf493feeffaa5171a6e88ec9c039640ad4052c7eac3553bd3cd46966831057a336a2e6fa567fa6c054233df7be785dd	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf7375bf0132c2617aaea1057ba5aeb31eb8173b35254565d5e13cbd87d36463baed7a8ac1f4182710fb02196ca737b1bbbe7ad4a7645715ca2770b865bd0c1f4	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f4fc18e891119b7925b86f8365d6def4bd758609bb63615ddc8eab4fc0e2c416c9657ee74100a62a28815dfdfcbdec9fd65a0e3577f281841776ff4cab0a29b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e462e976165c1c17f10d9a5477f33f8cc2bf5269b23816d1ebdad5a7ef03676261648763a23b8044814242f3ab7c791f2e77eb137fa95b49597e02dc121af10	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfea134380a0378391195edb74a2d5df5d6649f9226def693b7cbe0ba901f8a55434ae4f648b3a3efdae146e95127aa969ffce21719497f57b33a214afa3a7823	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	4	0	0	0	0	0	0	0	0	0
\\x144e7635f0500a0942a72028479a2713e6facf95fadb7d408f230e05802a7ea37856436f0e232f4a192509a3d77eaa8c8e3156c8523b9f0f286fe6ce6e03ccc7	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	4	0	0	0	0	0	0	0	0	0
\\x61254adbe3ca2fa0101546e1ae7a30f30df67174a3a1f93416429698dd0a4b4e3ba92b5292b26fb532466efa559dfab912c1ae18b9b605241b3f21e0cfef0c0d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	4	0	0	0	0	0	0	0	0	0
\\xa9a41e8bb16dc4000f0669518720820fc2b525d1b55099acb21a89e9e89dab59191b6f59529323e0dc20af8b6a89a7a6a234b0560eedcec9e11f8ce0aedeb882	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	4	0	0	0	0	0	0	0	0	0
\\xdb0e33aef9cf636d2dc73f425e07f54c371daba154d1e9ad5effcb2e0e70245c6652cb2c1444d8cd2978aca8dfc9199d23da24108acb6389ca93fe68a9dad7cf	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	4	0	0	0	0	0	0	0	0	0
\\x80d54d52d91ddd271c722a94a93dfcded7ee8b1a505bbacf59b613067d4d9d87f0401a67dbf13de48aec149e4c6164090e133e8881d20b3a8e542311ff9c9bf8	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	4	0	0	0	0	0	0	0	0	0
\\x6f495040932b543324c26b30a3c62c3d388ebc6c19f4b8f9b73607f8a68dde2b43c91320a1a90b475920a749aeddab9961961cd9f6adf48a0b740cc158ab3507	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	4	0	0	0	0	0	0	0	0	0
\\x01c247d51f73fa644734a2d3501d0b5b7d159f98fd215a71060816b066ad34e513833a0e6e64782c186b13d88b30ff652b5626dc2a915dea10e608a7920aaa38	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	4	0	0	0	0	0	0	0	0	0
\\x86166111d97dbe4cf17439397600d9c72ce8c9f5e818cd546ae01112ddc5d3b5cebf53dba7bfbd0a13103cc3efb4a950dbe528f4d2bdabf3224f8895607c0f89	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	4	0	0	0	0	0	0	0	0	0
\\x7ada7776985855afce6ed16d57cf6138daa420568f4bd195f7764f62032a09b28bd1f79799592d3d650dc81576e06dd40b71cecd06351df40ca3c4d422fc881e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	4	0	0	0	0	0	0	0	0	0
\\xd6a8f83843a02a1e1f8359307c7ec9618a91c980fa77928035960a4702ff316f24d8a1373078627e0a43d6f723cda5e76b4829b1dbcfb09132d6ec7356657720	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	4	0	0	0	0	0	0	0	0	0
\\xc40847289129a205301d65ff48d42c6831eefcd3a3581c243d04bfb30c6b313b9d8b776fcdb807e707516b0e5a307a52e2e831a74dec61050bf8132c1ba25164	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	4	0	0	0	0	0	0	0	0	0
\\x757b698c994015f6e99822c21fc8f94bdb67a90e1254b6d710dea6f6529c81cdd8b7c1d38ab810bcc78b1fde9f75b49f2097a2bb07701ab23d693eab36dc0ebf	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	4	0	0	0	0	0	0	0	0	0
\\xa603d1745ba77eda20131b3c5e5f3bbffee9c6086f63e08878df1ea2c24720264054ebd0483e29b27264f525e099e502cd92b3dcff9336f2cf6f31268581be2a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	4	0	0	0	0	0	0	0	0	0
\\xf818e7b277cf9afdce1193210b9e71c3ed48fe8f07bace65ea29e8bb973e426494cdbd014c9fadbd946eff9a58f0315435702d818826b1aed38239a51bb31266	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	4	0	0	0	0	0	0	0	0	0
\\xa9b86a52470353319ff7cfbfc99e12d1f88162ffb74e857e0f887d0d177ad3230f6b378edb2c87fce6d583f03ef81af114ed5245d8ca264a2e24ce442e2c88ba	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	4	0	0	0	0	0	0	0	0	0
\\xb5ecfa094236c6004b34d6e33a9d811e0b99cae895d65d996e0e06f8edbd53f34f8d8927d0784560ea3fa5665cdbc92b97498dee8a14670373af4e7ab64d162f	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	4	0	0	0	0	0	0	0	0	0
\\x5cd026d13b5ded247d90de2eac5d86126de88ac19cecf9802069c9686da79a1fc048ff77eaeab2a2771d6bc673c3e4a6375052f912ba890201f9ff481c1e0677	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	4	0	0	0	0	0	0	0	0	0
\\xaae7be1299d0c525dd09210726c86b449c8b78cf5cc7625398a20b31358fd63b37d21418ba2f2c30479f264a830eff9cc612dbe261f33375ca0f0b5c229f762b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	4	0	0	0	0	0	0	0	0	0
\\x8c3dcaab61d3f861e7c9055cd3f351d06389d62bdc57117bd8627239207dad8ace467db7ddb16e872a7eb3354fa62f853f8829ffc3887b530920b6c8386c6daf	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	4	0	0	0	0	0	0	0	0	0
\\x7f955f4adf1a1835e50720c052aecc7b858b64cd218fe24d14e17378c4ec0b12957150e1168cc2770b4d0628e09da9e6ae1894eda3b5744d4bd29a1ad79a5ec1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	4	0	0	0	0	0	0	0	0	0
\\xc46c2e1c49f32f66ecc4bb0543035b23db95c4821c7309c90f51eddeb4dfbe9c659b27ab3c63d26803dbe76d4b192071aceede103ef629e98e704a52e9fc5a51	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	4	0	0	0	0	0	0	0	0	0
\\x6879b59a855deb9175470c0565ec887c02ce4d56cfbbfd7b492fd5b2e761f52801cc36ccf9e4c75df922685eb7a238bbe4093c9cadaebe7ebd606717aa056ef2	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	4	0	0	0	0	0	0	0	0	0
\\x4ca3329235048ad3fa87887721365bfdbc11c037f4269c8f7e60034cb54c70e8b2175a15a1e8f3f66157c90939f626757f25ecf4e7eca805d45aa0d3ce4dc966	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	4	0	0	0	0	0	0	0	0	0
\\x937912fe8fa80481648407e83bcc149fe059056be23e9e47cae78a24a59debf5586b5e75becda7276cabc6ba5e4a05a5dd95a3120c4409c2ac971a7b3891b16a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	4	0	0	0	0	0	0	0	0	0
\\x3954ccac625c9177e478dcb8f3ac638350f1203fde4099fb6fa39b295f9c89c81a0c2057bafa5eecf1e7533f6966fc01a12306629632340b24ca8bdcc855bf9a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	4	0	0	0	0	0	0	0	0	0
\\x589b6f507e3009154e6e568f3598196adbd548abc7d1405bdd0afd39e23c5a53d93bf4bd23db465563b3292ed043d5005e8bd9cf29175c4fb95b424a70a2602d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	4	0	0	0	0	0	0	0	0	0
\\x9b9e29cfbd2d2823273f6dca51661766bbeb1d4586d3647c2776b28af26c69f0c15be39f1965d636ed7981a22fb343650c8fa5312682b3a6ef92b88141913096	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	4	0	0	0	0	0	0	0	0	0
\\x022a5065a676528c49a1a6192eab274a2ee6f090fdcf0907aae824308b2e7242f306e956ba0936adf66e0e9ac3a4739efa2f9cb87cd3e73a6e63ff7fd51c52d7	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	4	0	0	0	0	0	0	0	0	0
\\x27114c99d5664186bcc58cc43f7aeb9b7b61f480fb035dd43bdd8b027f9787fb10dc27eacb7489a57a1bd1244d142889af6dfa816bb1e3d70c7b703e1bc9db90	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	4	0	0	0	0	0	0	0	0	0
\\x4f99fde80afd39a2864d52f848353611b6ff7c670114955b3e1074cbafbe59584c50deea25a278ad22b24983b8cfef00707e7ade6ac680d8b6f6ee6797660b04	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	4	0	0	0	0	0	0	0	0	0
\\x60c0425cbac5ad0380fcdd6af737d941aaa8e44d8346db42529867b25e757bae71bc3d393dce60efa38342f022e125360f273c95de16d7cd0fd70e3e00ac79a1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	4	0	0	0	0	0	0	0	0	0
\\x49ee0b79706f28c035e25fd47fceba96b017e6f1564d1203ec098fbc529bb0f515ec39e78a7816b0e72ffae63b1cc01ab187c46f7f5396a577d5a996290c865b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	4	0	0	0	0	0	0	0	0	0
\\x811b20bfe69e30ce25db3be099936103c9a76f9602e38ac8e6616732d313ee4ee7e82e4283cb6902717ce95eecf823ef966f0c33f8238a8853002fb9f7cc9364	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	2	0	0	0	0	0	0	0	0	0
\\x5a7baec0f64ecc8a8b599e8e1a38a6c6374b80ae72efe86d4d4a8d5735714be17b35586ce30e8953259fa723792bee35506bcdb7d4c8d9680c190656a43877e3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	2	0	0	0	0	0	0	0	0	0
\\xeecf9757b62f371882a78dbd05c9cd66d0e7a83d76d979dd53f39157dbec83a209baa9458785e5849009f6b62b9b57ebb93463f66eb500f523d3fc23d677b14a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	2	0	0	0	0	0	0	0	0	0
\\xf1e047f433ff43647b3fd58fac6099f8c53d817d4081beaf080131af64d9df40b289e2dd455b601fdb4ad85e14598d2d99ef1d075241c9cfafa52c9400cc8ccb	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	2	0	0	0	0	0	0	0	0	0
\\xac62b8a8c2c77a0003f00ac92439730862236b1a3905f6198c5d77fb6abcf6012bc103bf42321023f449e3c3b9f9149e898be220e7da580ec934c9d9f14c5680	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	2	0	0	0	0	0	0	0	0	0
\\xaedbdd125682e34a285bc87e07659efc3b9a02f39a0a2a3fac9b31ba596a74717f06be3d5c8221f59f5e5c5150a56fe2f720035ad95c392ad448a803b13ef39c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	2	0	0	0	0	0	0	0	0	0
\\xe3a5c3b571ee7cc6cad46b91130b8f9063b0e1c951f3c4d6d10c124f1de3932bc9236d8cbf2c541a45c779865c4c37884dfc4b8f54669e6a974024638c9135b5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	2	0	0	0	0	0	0	0	0	0
\\xe5af66fe6568185054f2a50e07e725b1168fb48dfcbb318753a8641e3a2e8da7829fd10a23afb409b27a18d47077aafc1c580ca3a876a5a1e84f311605ddbe0d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	2	0	0	0	0	0	0	0	0	0
\\x2220d7c05679b521825bd51cd434dae5d87f4086d73761619d869fdb29af2348e25eb54d929683075202df2297366b3ad3083229ef36fd5edd2167967636e8cd	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	2	0	0	0	0	0	0	0	0	0
\\x611d80ec50294cc7bc4c2c816428d893674c5b82f1ae1907e8346efca15cba8a16c41782e70a540b4ea2feab174de4145e5bda26167e68ece1d15d1760d801c8	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	2	0	0	0	0	0	0	0	0	0
\\x8d03cb577af799665ff4f89610250cb6fcadd1ad10590fadc6fd67b2a0fb762b5d873502411944a0c8e71ee3d1e7dc71b87e626bd098fa0f697162c91599b883	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	2	0	0	0	0	0	0	0	0	0
\\x847b53012e9e1a66381fdb4e707be6a9a54ecf9f61912b7e6f698ee52da2be0b7a9f5806cb342f9e64f224668db04555d602d7eb000f7f57765ac9a4bdbccf0d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	2	0	0	0	0	0	0	0	0	0
\\x2033765a072673baa50e64226afde9630ef5e38903f72a18444485ca4b8cbe57ff0ffc2ce85f4b8d77804b5b7fd836df2ead89446e48a1c627abb84637bbae02	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	2	0	0	0	0	0	0	0	0	0
\\xc674c7c7d52377039c949eb0c31d525b04b0333a9ec9953b1c569e310a736228defcd6fcbab55c366f28f86b02d4267211d72c61cbc53358eab9a9b13e998252	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	2	0	0	0	0	0	0	0	0	0
\\x409c61d831941c799dfce41306bcab377e3cefbebbacbab04bbf99c18382163e3b23dace0fd8b904ca4c06d91b49cec23c50875f5edaeef1b06049738520f917	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	2	0	0	0	0	0	0	0	0	0
\\x19bcc8d2214700eac1f5edaeb7aa985e11281b064892ea64ccf286d2d280972fa275da58a00b36f82359672b8483ed69fe33b811cd42570da94e55217b73df01	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	2	0	0	0	0	0	0	0	0	0
\\x59cada19f700807acc88365ac1e563b631dfe56d7882ffe48132aefed260dfb757b5f5e70a5f7e2d8a14178d2e23ec65bb18fc2b57ffc829d72814771a47e2ff	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	2	0	0	0	0	0	0	0	0	0
\\x9e166c281c85fa7f86f49d125b2cb30f9f875f4c6d1fa7e46c12e00c4e4048c2777faa13169458c625839ea27dc020e7cac19df7a70c68cdb1838574e2f0a7cd	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	2	0	0	0	0	0	0	0	0	0
\\xff85197665d69c81553ddf90b291c36ab2a5be17f5af7984b940d6ee91a116613d9fb6d8d432413c327586b50d109a43053716854e51b3494fb4d084f1db1e3e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	2	0	0	0	0	0	0	0	0	0
\\x401cf3c956549802ceddd2f6f2a5de4ccb0794713912d04fc55b98402a58decb88c0dafca60d65a7f45499c914f5f41b2fda42c97fa91c76453da240547fba41	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	2	0	0	0	0	0	0	0	0	0
\\xfb0853ed4c96be8df2e79308ff43b9e4c62499602c5cabeaa26c324b8b62c2a16517fe80cd5c1eee51f43143e4e8acd277f5821a7a12ed0afe60fe54eb6f8cb2	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	2	0	0	0	0	0	0	0	0	0
\\x874708597736c80f83b8ec5c91a717bcdfabc8165ea323042e6b2f9304442c758260e3c6177d9f4a6d8a58fe73fd4d1ab4d18e833cb251472bf5faaba9aae726	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	2	0	0	0	0	0	0	0	0	0
\\xa08372a3596331671dc30d83c94699c8f813ac71f00f3b2791c1a8f9fbcd1dd442bcfbd2152e417299d10efdd891af9d78d4c9fa2fdcea7e7db9bfd1382b52ee	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	2	0	0	0	0	0	0	0	0	0
\\x8d5472881b2c97a52c51c9c31e07c4ba86f7f73361fc375a91870bdf3caa6026fbf6dd364b535681463d3413cf1c7d45a1d155a6cbdba0b82923b687e26e5fd5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	2	0	0	0	0	0	0	0	0	0
\\xbb9fc29fe467a4c54a95e42cda093dda94938bf35aa71e99d6fcf6f9e8d057dcb752625ea9a1c939194d94427cf996aa55b8b66c0f65a3bc58fcb471710076e1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	2	0	0	0	0	0	0	0	0	0
\\xd3c52b4beb3724d3d05381e85a9055ab888795cffd586251fd9be52e7f5b9cda525017a40ac5cf804d75c3edb6b9065fbca4e4c20d54f56054270802498d62c7	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	2	0	0	0	0	0	0	0	0	0
\\x30fd24752f244922d84e6782a53896eb8bfcdb8a9b23f8d089719b2f490378065f46afdd4a46f73d97a0b1f8f767ebe6b2bc82fb0b59cd9c6b736b3d64f769eb	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	2	0	0	0	0	0	0	0	0	0
\\x1b85714677771ddd9407fa150bf62704fbdd60b9d1222e1365ec4a8216c03a68039d02a0272da3db433a09df5dfe1d99dceb2594b9edc4ac9d095d8dfbba841a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	2	0	0	0	0	0	0	0	0	0
\\xe637a3f63e0c43cde017e4fec956e800ccbcea643e6dcbcb5ee7066abc2674989f46c851d5e45d4a0974111680ddf5a69821d79acbe39c077118552f2a2055ff	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	2	0	0	0	0	0	0	0	0	0
\\xce9384ff99d8e1424ad1c837ace51dc82849da246dffc27eec053ca6c607774f6c76c81445b1f3c1563da11ca0d7847889286da2ca0a5cfc9cb6933bf8ad1200	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	2	0	0	0	0	0	0	0	0	0
\\x57b36dc511dbd3e38b330ee00933e5f054ca0cdde870229f108f1bcb051f4d01b1f6c382e9554a92939c34493ed4ff58acf7ac967c3050d9aa72c3fb6f9e782c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	2	0	0	0	0	0	0	0	0	0
\\x8d0c0c477e5245842d280f4d20f301c0944edbbff147e0abbfc66aa5645e93424459456ffc0b1ae3cef310a8b9b40c3c25d4ca13de3d3112002bdc93076f89f7	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	2	0	0	0	0	0	0	0	0	0
\\x196a5907489ef1315889d91065978c557e9a34fedc24e3dda8f12c6d69e373dfe0ac39d68ae451f5cf764d21fc275dd57478dafe22d34190d0972fc0703296a8	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	2	0	0	0	0	0	0	0	0	0
\\x2eaaf8f209e9fb30f6dee5c15b5477fa75b829fe0afe5229241590bc43fcf400e8f21d66484ce608817ea7d59a204a875c287dcea65feecfd5e550fa6aef9cc0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	1	0	0	0	0	0	0	0	0	0
\\xb3ee20426a17a4a62171ed483052ebc40abb3aae042455d8fb3afe6dd7a327f4351548e40d514e87417508cdb13827b893be732b4ad480759e81c9b75d16f3d7	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	1	0	0	0	0	0	0	0	0	0
\\xc7a8212aece47cdc45ac7379c11feeb33b910360c461a83c4035bf42ed5ebd71db31ef0c424602679721c6fbf6976a978c2c3b5fa5e75f429a24493af55e5170	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	1	0	0	0	0	0	0	0	0	0
\\xe1ee74af47bf7a426d3e336a5f6c5478e7028eeb29aeb5b860a90b9fd7def36a0e88d885c3484c45fce0293994952dfda6e18dbac387d85f5353a1b37a21f384	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	1	0	0	0	0	0	0	0	0	0
\\xcc0b7ce4bebde66e9ce47e16e30a8036d6f63e6e0a2595f4a140ddf051cdc9b53663b53bdd057b102ea92131f65b2900e8fb83942d05db336cc5ad9875408079	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	1	0	0	0	0	0	0	0	0	0
\\x601350003afcaacf552e2b825525fd4e755b7841b6d5e2f81f37e484e0f310cc315ce62cd3037834a79ce466e00e1f2e8821cb7a0fd9d29401e937bcddd13290	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	1	0	0	0	0	0	0	0	0	0
\\x4dd96096acb420c7dd22c48de1de59fa6f908de1e666877debbcc8c49ff85816a4b83d62ad88cf1bfea7a60a36024dab31c4a954cf498c9b3e3c3aa10d125139	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	1	0	0	0	0	0	0	0	0	0
\\xd06bde1c5f36259d327d7a3f775f708cd22d61bb3fb643f20a0adf3938b307af0585c1816fbae5dfad7915ef1b4b962d9d3be382e8cff1b1902900adb211dfb1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	1	0	0	0	0	0	0	0	0	0
\\x639aa9d5135da74a9078b1463c35943e93190327984f484ccd38a5c2cf3331dbe67a1f4c22a91d1cff9b3b966b6e790a2987bfb623bd78c2e947b50b84916afd	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	1	0	0	0	0	0	0	0	0	0
\\xb844600bfa9443cee95e523b60d343f6b79847638b89ddeee82fdeb2de16a8e839d960393c27dde7928e9c6001cfe16c03d3d97e7c7adc55c0b7b75808ed1f56	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	1	0	0	0	0	0	0	0	0	0
\\x7057dc9a00d6291d8f59112759a8d8b52ebb514c88c3ec1ece12173da98664a32a2ed57285b9411014cfae94c06cadf5b3bd42e2cfc867da4ac3ad36e1ded630	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	1	0	0	0	0	0	0	0	0	0
\\x0634378bf38e1980b54e4a47894cb4e5833e70a2bb2cebd58c45bcd9dc711ace44b87907355aafa81577175cc226a914839fd9a31bbea69849fb3ae2c5d85216	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	1	0	0	0	0	0	0	0	0	0
\\x0c55ee2e90ef3b7f55d97eebff7947190dcbf900ffe51625a7d152a2b5782f75601e76f2e8dc4f7e73c3b2dfdc66a37d7684d8e73733dfc24fa1be167a0651b5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	1	0	0	0	0	0	0	0	0	0
\\xcddec53c76c413403ab627c739bb05cf65544c416cb651b23f14052de6e684c6ff2a8a5738197978745a3402a4363bb94d72ff14a2d798d3fe3a9ce852b7409b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	1	0	0	0	0	0	0	0	0	0
\\x02b45ef22006419fdd9d334733da04f1ddd7702a5431457ab5fe0302fdabe54360d67acc44fa364c7f452e790e2fde28c060c468f49091abd55d79b4cd3bbe89	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	1	0	0	0	0	0	0	0	0	0
\\x81475d99e33bfa71676522a61e6bf8bf1ec73da2514bcf5c45278e57808ff79bcd37dda632d921122cf0a72ee4ce81ba8136d8a5515bd895d0bd8ef49d424bf2	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	1	0	0	0	0	0	0	0	0	0
\\x0503eddb02166cd3d148d754cfe1bde46aa459ed654132e35ae10f67d381c0749f05adf1e02cc82159ddfb2a638cfbbc12b9b7cb66d5927fb8bf4dbc761b3077	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	1	0	0	0	0	0	0	0	0	0
\\x0f17884672d768d4544c99fde98cf75e8d3bee60a36095d5fe75265927da04df52443e0d14b573012aea5fd0d461e5f470f768d476db28af8232b480878fdb1b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	1	0	0	0	0	0	0	0	0	0
\\x9bf2631e4964c49ad41ec091cc7208d62b36a100ce530f3a356049b9854d9e542822a39e5c8812a51ac4429955abe3c0dba002ae2256dbabd828c2b7ed52459b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	1	0	0	0	0	0	0	0	0	0
\\xa085174a81c1c1a72a4cf9c2bdaef19890dbc7b513533c181cf9e8983c29e4c861b2e60cf514c017594b0ad8a140ee4095d0a69085e0d91307e4eae0bb36b87b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	1	0	0	0	0	0	0	0	0	0
\\x0602c3d5498cd10db8dad07f3570354115cec14ba6429bff79286198a8f325eb30331e7413ea1e8d9efb74b135bcc79a52253be487133daf0dd99422dfcc0dc9	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	1	0	0	0	0	0	0	0	0	0
\\x981e01d8272266d29cc722d959a940291d47749928b93d23beeb968f7562465bb7721767763e1096b761df96e2c66d4fba652b940457919c1626e877873af2d2	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	1	0	0	0	0	0	0	0	0	0
\\x2caf96d553b70fec8a269512a2a28c9a891f0dfe1da5eee8af3c461b8ca16a6fa5b7a62b5213c5d174d155f5a3412c1d2a8fd36188005035282c1494ede39cb2	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	1	0	0	0	0	0	0	0	0	0
\\x2bb378bea70a6e5193a42daedf56da41f2709183ae8c32b2d33c2fd310fd0533859a829c986ab679ba22008ee986a986d45b15a822b92b55f80c69cbdc0ce3ae	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	1	0	0	0	0	0	0	0	0	0
\\x3f79cd4a8ce80bbbf6a24df724d50b3a2b035cfdddc7ab3f8d8f4945a504aada1c51ded84afc66eafe90f7015540d7c0bf710820a257ff8f705cc073e0ec4eb8	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	1	0	0	0	0	0	0	0	0	0
\\xe12982d1cdebf3ad46c8ec5c0ef4024e06056575bcc87d43310748e89b697170c38a29d593a9ec840d60bd7d3149cdfbbd5bfefbf666c86b9b42c018f28f0562	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	1	0	0	0	0	0	0	0	0	0
\\xa2758ea42daed99f8f1d53caa5055074fdeb83d97a1eb0fce3b736bfc95e52f5bcc212f643c3ebf4f9556900e7ae6bdbdb8edd44a092b9d5d7a133d7cd41b0f1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	1	0	0	0	0	0	0	0	0	0
\\x5cfc74b8a174a8d92abd2ac0bbaf517369d89caa1a90536a8b44500ca243b454a634fb1f04fba49f82599b99c654e32cd78b5324ef5d5fee8d7ee72d5eb43d77	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	1	0	0	0	0	0	0	0	0	0
\\x491ef0d873d94eca7be7bdbf22fdec8c44d5998dda2b3db37a893c94f7d796ea82821678ee959a7a24b93d54757b1e739cb253fe15720cf6d8a1bac537189635	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	1	0	0	0	0	0	0	0	0	0
\\xfdf6fce704f239fb56b135acc78b3cb1b82c8384646522f6028a552f6bed0c11c2cf14e834abbb7ec4377a91f8fc3814150ae44fdc76da4aac7b1791770f30be	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	1	0	0	0	0	0	0	0	0	0
\\x531d3b261f24e3ee1716cc0b71b83f5f04596464ecb8fe685a7cddc819a3f6ef2c6bde68d8070035583632602f69ebe5270252590e21971cd87ced7ca43eb96c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	1	0	0	0	0	0	0	0	0	0
\\xc4a54823926d8e927a17ded9dcf0a9dcfcbfc48108033313fdc133ea87cb7b3eed9c9a30ff7bdec85a0c1ce441e9b3e4456677e6c04b4038c3a4eaf179a9bb80	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	1	0	0	0	0	0	0	0	0	0
\\xbe2875a92e9b17e3c1ece7d44c8d55dad2de90abf4df99aae6b7c9617f6f555419a32698403434e7289d7544b6760994be58871d9eb6c12e80d68eeec3c01bc5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	1	0	0	0	0	0	0	0	0	0
\\x6953fa324f793b3d36c556f214d946304a1a6e870c475d3b5c27b3e6afbb853c789b52e0ad6cd454d76b996863a47d8a47548e99f2e0d2d0d59419256a3ced58	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaacc526dc1958a857ef52630bd5c07ef050b00ef4b152fcf6313e2ffb6b32e4a531a79a980b3b233ba5ded9cbb5f29752638f291890a3b63a5b23899ef4b9d96	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xee30629e1663541f498d4fa2331c8f7544911cd036dbb5ed1db9fd7a671adcbd990678f52d47b41e3ed83758d1ea8b244d6be39034224e96f7717f9780ae0815	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b9012724b31bf19bd4c3e928cbb6f179e9ed04d6622a35926302c006e02b270585df18d7cca89b4896e63283b2e4b3a74ec8567be3877fe263245feb43643dc	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x293c4e81abd47824b475ffc57b3f46f0d77399859c57ee0a7a94ddd1f97874c4bfd0917ded2463c29a65f544504ec933a8e98cc13b6f29c9627f31a2458bf723	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xebc604f7e8db2c6ac5df8d5b972430353c60dffeca877dd29948feb589951c6162526d3f462df590d4ffc80ce8711160537ea78037e216578534dcadf234eeda	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf7f1422e1255813f5155f54172c08aee07db5b954f3dc9c09961c47659f909a7f21f0d5965e15daae7a425a17d3f67fca89eb3581344a89423901f495ceaa0c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4eb12b082b7f5d92930ea83bf62559669401b9a3a67d4d9fda4b463f89d13cfd284a7ae5a6d4a0175fb327c1d28d8074ff9dedd134895a87a85c1b29de885ce5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x823e915da0ccda6a2d75781fe08956207598ff344b66fffbdfe0d1c1cdab6b79f527a4f9383a242cbdab9f40313e1cce5a219ce38e6d3cd63e358f1510676159	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x327d29f4ab13cd58a8dd76f568a3fe65bc1b0265e61e99038914276597883ba7a724c49e2eb0534eb75494dce8f4a6c2f79145bf268e6924f1ab1ad7f5cc2bb5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x54635038b4c94207cb20ba5e0ede3158d5dc4c1db5ac3446155517d7a2cc2f9ec00062dd7f66063620ef7d7d6d3e87c304ec9468cf23e0d46dd35ac1e0f74ba8	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb3a338e307c9ab770df7816de03bf8ba911cf848558648d52263a64e1ac1489875a0f4bca60e804a24f534d770748126e9ea38ba12717335b34ab8b686d6e0ef	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe0cb50556e13a70fa3b24079109a698cca89544bfb24e15cc4a8b89b5695345346fcc6b3cf035ecf1526405023b32f52cc3d4538e07bb9a19fe722de02ed62f	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa866945783875ea04de275cdd2e7d8bf7450b03c6cb9c59b00f38ce10c41ae214cfcb4d0589f058550376cc61cb3bfe56443e7a1bd09e09dc02a85fe32a0da67	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4321ab3b393f2498f88299f02179de5a33f21ee51a6dc4b6c740c94e49ff6aa250173c04e197dcf05bd3b5f65e5db4cff2470102f84d9c0134fe5dfb959c97f6	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6f37cc648a7c8e1c7d8cc594623e06a5d2b88a2c0c9a3d40b69e58844c2c1828f0827644e0d4960983fdbf0e743e746aeb69521525ebdf0d92b8655fe1c08d6	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf302b274d1b3a74f7ea4debfa41eadd49453817f6fe943166bfef905a1e6fe61070a7f2547aca86943127e7e27ca8ecc488eb7a1810d1a710b9ce0cf10eebaa	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xda07628796ca3015e175ab0779b15ceeabc373efc655b8d9c9a7d9a3599485c29f322a66e0c19739519583ae74248764d85583ab2ecbd6710693d2de3d1bbdd4	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5fa228ec22bccae4f9e8353a4dded74d11cce3bf165cf3a74fb5cd7707d16dce66c7dcbfc17b02c45a27612c29285a4d04ac8387ceffe959ae5ce0e4ae4e8f24	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x70e9e1a5395df7046082218541797b96e7b153567410959b4118d3e911ff43b4483b9f5173ea6892700c6f21ee959c4db4e036ebdda3948b4413acb901550e80	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9354555251541fe3752c70184500f33d5a9a0c538ecaddd1aa2940c4b601110c0b23d4445aa55b345dd12adb6970d21fb2b269c12a319add26114744b535f9b7	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c4fd2578a9cf31067f7b0ebc7bfdc079c03126b454e50e74eeeb33ff733217d3397d177da5c2b25bc4c788cedad3aeccce78596732727d15fde4808c47e32fc	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2474dc5ff318218b8a751ddd1c5459dd7dd41711585cba5fccbacd39ae4a95f46899e921250fa6e415d76557950a83b1161def1c6a632ef4db7574f023af85b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x665b9d95860f17738278b186d8c88015fe1aef424c80a5be0372a6f844b7af077b4b244f903ccfb43f7ab2729f0b5ac1884fbcc1affad4501d46c24557c723f0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xafbd293ca7e06f57fe328d5ca2af34276a502f2724a6ed1ef48a19b25c063245f9e08d22529553e5066cc54d73bc624cd674b535d87faa4fb6615b584a801b49	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x44a205ee7ae09b71f279d7804a46615bffc4afccf197092ca9d1577da7cac4593511fa7fdfdc44232c05c35a4ff0171436aa26503990afdb08b415ddba64ced5	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xec46060a5f4b86666183958cec314791496780d1c928cd78d26a8fdf372fa68cdb860d3dfc4fd1c50c2e4699b00097a0225c0513f267a19fabfde295d81140a6	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1cac523568d013b22d1fde043facb875ffe16a5cf001db51c6dd5feda3204b4562c524c5646916796e623c1f14343bea9326a6a253e33cc84cc73b8601edd24b	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb1a4cc3ce6c80fcc5c6e874bd8a0e34716493a11eeda10b736e8692a902b0c0114188696b451ef683f65bcd428944cd3c2c936421b0ea7eda39702a6e368df44	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6cf0d8001bba9fb6b5579bc5f87c035fa7e953e4a3402a4e0930baa60b234bb781e427f0b819cf190c1b5547616497e46a4790b5383490c0904f3b982b0bb66e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x16f9bbff393d86bb0545df1e34c9ec9ffef2c1388ad00203ef22ebde57237f111e11a9497b83983b52dbac87021a198dc65ffa80e04c018b0391baf09e9f3d3d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1921d59f98a832091dd9334830803dda36f1b28a3ec4488362134b5d19e9b5ceae14de0c6ee576e0fa23324ef5f77f119fdcdfdf878d3bdda9793ea800be14dc	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe4cb0bfb5ede40886b91a5dfb1eea5b3ab4e2aa7cf6f96dd57ff180cec6b0ec207245b06474a8d21400a4885daa5a5f8b8a16a9de3a9f37756706d4b3c9bcb9d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x07c5fd1e4ca3d2b42adff89d1ac58a3fbf2931c4fff8d7e3df24e9bfba5cdc2d8bdfdbd9455b27834ccbf746baf2f9dae313c99bd2d9505939f60ea1be841f43	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1566680026000000	1567284826000000	1629752026000000	1661288026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xe149101f92a1d94ac50c546ab6e78ad1a1273bd10ae476d60f5a009c4ab62b7b57a9cd06c00aa2c95feec3eaf2d58b7fe2efb207433736dbd5c54ec13aef8fe0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567284526000000	1567889326000000	1630356526000000	1661892526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd7126b4e9a9963582fa0c88a5ea6dea2cfa29b3bdf80ee9163cfa46536eb3f8c9797a782b41c2d0c21590163fd34c88eafa259f664e6b632cd7fca5e1850a843	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1567889026000000	1568493826000000	1630961026000000	1662497026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x61c6bc9310caa07c1ee56762ba70d13e4e9149ccb7ea768b9b852294459a3817a498fbe10d0c4a72cd1b9265f9c3ac8817414962179022c527ad54c9250e2b77	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1568493526000000	1569098326000000	1631565526000000	1663101526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xadd0e60e2926deeded8ae878a8846e8985da603b1a112275b7ff64dfa868e79d1a0d67426a2f204de9435007152022c87911db26e2dfe58a56ee5226860afd9d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569098026000000	1569702826000000	1632170026000000	1663706026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x99cca86a5d3abf61e0d2069c27969a5d2ab3d74821b032cba6addc4107022dca6cea7bef77c39cc86f8c45d45635b359a64642c30aba0fcd60d2ae9bdae544fe	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1569702526000000	1570307326000000	1632774526000000	1664310526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x6eb3ae27df2fc2edcf6da0891268f1f15d78cc57ac330393f9cbe54b36d2c7a3089c447d894a5a80433ed2fa9e0235ffd07eba8f322f24440b060a17fc05c9b1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570307026000000	1570911826000000	1633379026000000	1664915026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x81e77959be35ca594242269931e3276f85d402223292cca49c1960693af5f41a54846dfbb34137c6fa62de72b0240e822cdbad28430c1f4332142670fbe45217	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1570911526000000	1571516326000000	1633983526000000	1665519526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x7fc2f0d768b1ee99ffb600d9488cddb21f627e17e29bbc2f0f6c5a9bac453b04fc5e1087d065c8701c3e82ff82d6f127e76b2573f9407ec96c570119245fbe36	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1571516026000000	1572120826000000	1634588026000000	1666124026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xb70187ed8daa1ec2254e77628714d8ae3973c7b767b1b4cbe51858c8732d6a3c32c4fa109a66e770e0c33de2c408297223060b47bcaefa680b74e1f8ddf0d2ce	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572120526000000	1572725326000000	1635192526000000	1666728526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xbc926ab059a6a855be449ad1192050d317bba4af28a6ae6255e50742cc6884b6b915d085dda61b0f1ec6f0439405ede15a88db362a9745dd468fe9e5d6669bc1	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1572725026000000	1573329826000000	1635797026000000	1667333026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x7a94a8f623ec0f0c85a7a2ae55c56d92224a0eb3ea85a2fb9ec8711e4ae136c5dac0c2462c41c57908062a474167a5d314788e1c7b129f860b617b09ba29fec8	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573329526000000	1573934326000000	1636401526000000	1667937526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xfbc61688c4b751fd777e7b2976957b56836a20e2b3ebb40588f03cb9b93ce71d694d70d620d4a85c4791b4c03c5ab290d72716b9dd6b4bb390346ff49ddff70d	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1573934026000000	1574538826000000	1637006026000000	1668542026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x9a52dc7cef13d2daac43292d787a74b40ff10ef4bcb90aaf27ba98f0583904625a1919d980b9caa83387193290f00eb062850dd8d6f6635ca0f2df8706cf4a83	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1574538526000000	1575143326000000	1637610526000000	1669146526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x432282fa4b116500979ca87487110d706835d1c1d8dae3351ce6536b33b959335759eff9f3e1538e738bd99fd192a77ea3553a7eb566e4a5dce4389f92578e9e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575143026000000	1575747826000000	1638215026000000	1669751026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xe0baaa62d19d35196d57ea0f0ed56345f22917b54809b40cca67ff3b5429ee383ec9657482f58ad9f3e6d0b41e366c9f4d6d8c5de50dcc98c57c2f26611a9617	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1575747526000000	1576352326000000	1638819526000000	1670355526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd771361d92cf78aa62f52e66229bcba605163bc55d60414d6ac3d50e6ecddb4b04cc38899910e98a34049e9e3bc5fcad870967fb175095a891ebb0848ab3aab3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576352026000000	1576956826000000	1639424026000000	1670960026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xc24f5ad58e6ea1ec3451160d88641e5d88d429ffdc324ccc2b5f100a17d1dc4126a8a036930fe44937e344d6903a17af9f8be56463971489809c48aabcd6b368	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1576956526000000	1577561326000000	1640028526000000	1671564526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x1dbdf2ebfbe7890804c7e36cc62c89ba540f36f1e717b814cfbc793777e66b4f8ff8ef44bd9d6c053e20d98a09829994868b3a9af1cc81533f276750b921977c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1577561026000000	1578165826000000	1640633026000000	1672169026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x550d0c395ca94d2695544639c008623b60ad8e7014793006202ea7fa865c309101e9c9cb615b14fe2174d62e39916ecd53371c9aece9fc2147f5d7e32b0537f3	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578165526000000	1578770326000000	1641237526000000	1672773526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x2bc524cbc3f42423b6a8cf33dae8e91ee890e122c8689d7acd59f375cc42f40fe53480f49fb4808baff450963f81c7ce68884d0d5958d09a26310907ce15d426	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1578770026000000	1579374826000000	1641842026000000	1673378026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xad52de156a4be178f90f46989ce30c281070ea91a0d74ec51eb3ce3e5b7c5959a197b875983cd7f24c46e8a28519febbab702a5e511267961272edfb1963e37c	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579374526000000	1579979326000000	1642446526000000	1673982526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x58579a0de5e4e1e98746a946a471bb8ed1215dd1c29049d36eda6b450ccae172f562fc4cfbbb781e54bd95350ed9371507b1e7009ba682039f4c09c011831bbf	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1579979026000000	1580583826000000	1643051026000000	1674587026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x64ef45238a4e2adddd65f355421a937bfc29ac1b4d136dffe7d14818b66d6c905883de50167c50bd0cfabbc5a00fe068d52488ac0d17d251acf42f67b7b7d56a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1580583526000000	1581188326000000	1643655526000000	1675191526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0ce9df5cdd6fc84b4f8110989957de48d8142c453650fd92c8799f2565b07d67433a97f99bc65a68ad44af115d6fe774292442d69b80573a659e1efffb08e6ba	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581188026000000	1581792826000000	1644260026000000	1675796026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xc91ae6fdfc3f54c635ce9dc240a14d6d3af372702ccedfcb9c69ec17d75c71c06f8e4c3eabc59696a323802c8af05da4c4ad2508bbea7a6364f80eb80be722cc	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1581792526000000	1582397326000000	1644864526000000	1676400526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xc81faf5191d557791dda06c9e0e6f9b60993b273fd97a7a575b97e90edd5334e9e0abfed101f9fe9a3bf8d038da0fcce5e0659fcbccc0a4e36b63bd035318dfc	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1582397026000000	1583001826000000	1645469026000000	1677005026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x49ff444aa987b0567b6efebb81498efcf3dbc7250e87cb0c280c62b2d20e73f1d9672c68ed348c40e28057ea76517c3b3be335b7a6f7b56b1ac2edec4112fbe9	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583001526000000	1583606326000000	1646073526000000	1677609526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xa91a05ab86a0d0861ae4cdd6aecb4707eb1ccc6792248cf1a145f545c987addd6ea7f84a35bbdf3c1960d8c8c46b515c9836c87a26651ed9ae5e02224d56f354	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1583606026000000	1584210826000000	1646678026000000	1678214026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xb282c89330e0cde4d0e97b8275b620715aa9b2178cba3944f32a4418f5a42214c00e14b7b49108019ce779a4f55c73406b2dd9ea1296074ebaef6b1925341195	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584210526000000	1584815326000000	1647282526000000	1678818526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x03bdd7f0b33d52ed324ffbf8e9940667d26a237b90324d4012c7e12aca5066c5d24ab44ed0164dd8a46192501a029e5e952ef81b942452e06764bec368f4424e	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1584815026000000	1585419826000000	1647887026000000	1679423026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xc8c0480ac4fc06e4d2179b563cf80da8022b6c8ec6f490d462b6cf28a000168eab62c466231df8cd7be0020dbe10b8d1a896ae778873d65167211f73e42669f0	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1585419526000000	1586024326000000	1648491526000000	1680027526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x372b76610621a5d923ab6476d021648a63ab9f5650c008d207c54f7ea0dcea25d04139b8e3f5f4117159b0713755704315d9cbb53bb849bf158202407201d86a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	1586024026000000	1586628826000000	1649096026000000	1680632026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
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
\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	http://localhost:8081/
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
1	pbkdf2_sha256$36000$WLL0RwQQZ3xQ$096WTX45BDUaoFlQ+vZCI81kGCwTPA3wi0nvNsqrco8=	\N	f	Bank				f	t	2019-08-24 22:54:18.055465+02
2	pbkdf2_sha256$36000$lTccc4Souwrd$EVajYsGEZRsFhbwkbDDuxapX+2opc6kGP95MOV9PQZk=	\N	f	Exchange				f	t	2019-08-24 22:54:18.286214+02
3	pbkdf2_sha256$36000$xmNZEVO5JNJX$ughDjlhK7nq11vurGg6ckxhqnlEP0/+0D2FPOlBSWoo=	\N	f	Tor				f	t	2019-08-24 22:54:18.385104+02
4	pbkdf2_sha256$36000$xhXEcbWyuENL$tNAj6W5fFgLn8vVbgPWIQTRFRCGbvS3bphplLvsBld8=	\N	f	GNUnet				f	t	2019-08-24 22:54:18.508724+02
5	pbkdf2_sha256$36000$kvgVEzwmxmBA$GGUwmGMs+otVpj2DR2306DySvj/sXZEr5W4PEh+lvpc=	\N	f	Taler				f	t	2019-08-24 22:54:18.60656+02
6	pbkdf2_sha256$36000$RPgeQoik3UEN$MfIUORY9tpOFCLr4AWSvoqHygw9Oe2KfOke6YcWn45I=	\N	f	FSF				f	t	2019-08-24 22:54:18.673289+02
7	pbkdf2_sha256$36000$M7KEA0TwJH6g$RSVgo0CxtfKd/h1Ia4varTpSdDikzi+6vxbHkaNB/tE=	\N	f	Tutorial				f	t	2019-08-24 22:54:18.729265+02
8	pbkdf2_sha256$36000$k6D6Q79VckZm$gCXbVXvFkr5V7Ns5+DVYkO1zmeAXvXZ/kGguQUBHKMA=	\N	f	Survey				f	t	2019-08-24 22:54:18.818069+02
9	pbkdf2_sha256$36000$0UVnT1WtDBv1$PIxyVKWvUdq3dwOmBhj2COuzpFQDQC8bdtvH9gWWz50=	\N	f	testuser-F6nitOeK				f	t	2019-08-24 22:54:22.698065+02
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
\\xdcd8f983a92db54f2291b728d4e6ff7ae1916bd94255a240509bc98409c6e3e5e127c8e69645be261a17c28a4073540dbee632d1f17118ebe4bb23ee122f4128	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436384345364136374431334130414145413536324442414536434138383145423837303930363343344342343846314143343841394336463235424139373439383239333042443631324642354230444643324236354442444534333531313839363335434238443741413041423036354436314337434234463543353834343239324443343430434142324242314143434632303431453943383135363445323046394646443537453036333746324237463432373931353534333431313234353034443636423145303246313830353232453734344333383038323932394231344238444642303238384133394342413830303733324238393043333523290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xe01680f58d09cf4e716ced759bef6eef8662874df53ba1abd8ede01007fbd9b3a7f6a4ad457d61ab50439ebb429eb46aeba07737e9bccf3c9ba86d8a2fc08c04	1569098026000000	1569702826000000	1632170026000000	1663706026000000	8	0	0	0	0	0	0	0	0	0
\\x960fc30cd57ca7bfe62fa23a95a89f4901be052795ece5c137da068e67dfa67e51920885a72ae7f72799840d0118c46f75f974d4bce93a1a6e98b2b403696e12	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435423238323737334645433933374246383433303538383342454642424332393946334542354642444430313543394442393644324336413735313232334436364646303832304534433045424645443431324346353931363030393146393035354239384342353930323239463442334441373139304438313837323138413735303344434445394441314344453044454439363146413433344532413731383535363837423532423230303035433731443842383930323033373144463346303135384345434342344338393436434630384141383838443136423938303444374133353644393134414646423246453142433637453239343344424623290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x12b08bba69dbf93d7a9544574c77a7563de471ebb8353fd3827721d7b8aaa5d7a14820b397cc10baf3b5b9734798640fb4b86d7de87e4f5dee86ba2f5833f00e	1567284526000000	1567889326000000	1630356526000000	1661892526000000	8	0	0	0	0	0	0	0	0	0
\\x015c82cf76ed65cfda03774f6d04e6011e305987112e3b03610614a2e976629df060c16180d605d538d20c0b70c9af9a9e857cd8d9121f9941011784715d1eed	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241304645443442423336344342333833323542423438373230443935363437343235433034413343453238343232444339384138353744333343354434384636414344433045314139423531424445413336383141423432324530454541313237324137393132454146423432363545323741454135413331414446384438344139444335424143344345374333313133433731434241463130453030413342313241343830314338354545353142443332333443344535373338303137343030373234353044354146363034453842344345443737443732413538443837383230433731423038384144304144353331303544364231433832433336413323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x0dc4de97010d52aef4e9878ad15d52b177b42015d35d5e8ed720de7e08d38443ffc8ee6818e5cba26e4e4549ffd592ba430f85a5c53f64bb23c3210aa2d0690b	1568493526000000	1569098326000000	1631565526000000	1663101526000000	8	0	0	0	0	0	0	0	0	0
\\x7a0dc43e5c08b71876cae99c17373fabb225f678af8d7ae121e1f6c57eb7bbf15fe46eab1fd9e9baff5aafcf68cc59661ff62a4b8aa684404a45c3f8c6f91d8b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431373146393037334435453138344135303543373136393944424445384342353245323735383030433844433131363035443346433032354345453941353433423942353846333934373545394334443430333145313542374431303436413335413238364234413631343533374236323243363437433742443442463933464535414433344344433437423845413839414544433035353039304331423743414142463645373032414430344535453143463338343241434430353944333746343045444641333741343744364330453437374531313642313643373532413737454342313346373334374344393031463545343039424545334242453723290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x32ae060a9e97e3fa87dd45b1d3802fac45a0f88ce6a956f1334e03978de1b3efe0b138bea063b6ae968cd04694f62d5063b605f1f7c30c3ddab916fd1454530a	1567889026000000	1568493826000000	1630961026000000	1662497026000000	8	0	0	0	0	0	0	0	0	0
\\x1143dce93317f2e1526feef87fbbc95a748df208a2078ca3ec55743a782d63e36456538d89ab84f097b6bde0cca9835e0c8f4aeb2658fe8b0d713473f806e688	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304339304239343536383634333034464235453946443531303846423035413232383243343839384133414232324145353342343633413243383645324245433345373742354145384438344336424333413331334346453046383839414546303836323330344338374432413635314130433034454245393546353335343735454244453639413933453635423034453430373136413736373637453346374533314533324344444246313442383141334330393033453543394242463733363544413232393146424639313043323932344239334342463538344239454541333937433745433731304431323642423034464237383439413033444544353123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x6191077256d9abf2127433bd46d51ec0fc95c2170de1ddd431ce597fa8553ef872b7aa2f27efa8742150532eb312da5d0050d1c60293ac7b7848cfaaa3ddc00c	1566680026000000	1567284826000000	1629752026000000	1661288026000000	8	0	0	0	0	0	0	0	0	0
\\xdb0e33aef9cf636d2dc73f425e07f54c371daba154d1e9ad5effcb2e0e70245c6652cb2c1444d8cd2978aca8dfc9199d23da24108acb6389ca93fe68a9dad7cf	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304545433944453136303434393833353736304634393946433535373037444531393037363031353835364534363834363232303938344335313635343546464439314235444335453142424337383441433039463639394638323544434630313339363738324635303033423031443933363644374335433341464230314135443742454444323446343843334441334244393836304134323739313041304245334238424632434633443546393645353235413632423637343434444132393246323545393833303446443534413331324437374243313938454230464638463939323941393445374344423041314446434431384235413544463246423123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x5cf527f9ddab848233577a7fec140130120a7ac59587b597b744c855e1b59692abb14ecbf39d651b52aa056e1b0bdb33c869ffda375aa033abc3adf1428d6e0e	1569098026000000	1569702826000000	1632170026000000	1663706026000000	4	0	0	0	0	0	0	0	0	0
\\x144e7635f0500a0942a72028479a2713e6facf95fadb7d408f230e05802a7ea37856436f0e232f4a192509a3d77eaa8c8e3156c8523b9f0f286fe6ce6e03ccc7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242453731334435443031353237373135344331334438344332333335324341333332333741424544413236354231353138423542393541363739343144413631463642373239373736394332343738464532433039383145304244363445393338353635333645333644354332423939383934323438414446443936313043433746453338424231444142323442313444463543354444364333383234313242463545344636413930353539453231454143463945354645333642413039414546333536353731394233343932454132364244463044334137413830413642343938393541444430393946413835323744453339394339323939323441374223290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x93cd69475eb45d540e1915b963b5d51da5acea7efe450e8325d5466150abab0b1ca997d1fb5d8ddb9a25d49b5629d4ef6ee0d10120cb07aa0d350e9ae6e5f708	1567284526000000	1567889326000000	1630356526000000	1661892526000000	4	0	0	0	0	0	0	0	0	0
\\xa9a41e8bb16dc4000f0669518720820fc2b525d1b55099acb21a89e9e89dab59191b6f59529323e0dc20af8b6a89a7a6a234b0560eedcec9e11f8ce0aedeb882	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338433434433944303530393030463043313136464338393342343030393942414344413530383046374433444534314546343644344534413642443442443342383245414344314334383939354532324330373137313131414446333035374232453332443146363946413833453236334439373533433239303334464530303134433443393738363230424638394138323732424636374539363636313431424142464333323032414534463234363443384131363836313432344643373139423532363339333743464132363245304636413631394646373931353730333131424644303736363345314538343636413445454134383043353832393923290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x6e4a9926fa61339c01a277fc7d0f6cd6dccd55765d2a5d92be80fdbdc4d82a3428f6381367282ec3881c6ffc3f7dec9935cfb3d87b1bc4b8cdd9adffb7a8c00a	1568493526000000	1569098326000000	1631565526000000	1663101526000000	4	0	0	0	0	0	0	0	0	0
\\x61254adbe3ca2fa0101546e1ae7a30f30df67174a3a1f93416429698dd0a4b4e3ba92b5292b26fb532466efa559dfab912c1ae18b9b605241b3f21e0cfef0c0d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304234344538464645424133443836433037333635314646383137323137313334383035444643414233394243413535413430324644453935343934374139353244433831303231453841394442454444323631434633454641353043443042313933434542433833394631444130443934353646454238353743433736323533334641413030314536334636414330353131303334323437374537394530344638374342453944413635323130363233434438423846454536314235464232444132443232383244304439464139374632434145313741353342394341413535463536453338414544363039383033434444433745463435414542463636383123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x0c6a77f3bb27291ab48af79bf5c8459855cd1ed5c36358cd03d5f13da89143e294af29bbadb36196bb8f6177b8d17fcb3a53a531e19d262dde9393678adfe709	1567889026000000	1568493826000000	1630961026000000	1662497026000000	4	0	0	0	0	0	0	0	0	0
\\xfea134380a0378391195edb74a2d5df5d6649f9226def693b7cbe0ba901f8a55434ae4f648b3a3efdae146e95127aa969ffce21719497f57b33a214afa3a7823	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439354232303134444143324245374236394444453443363246354437444534443735433535394244433642314531363342444242434433413737444534434545393837444544333437424132303641344441393443313932354445424431444639313330423545383146413631353433444232364633303535444344383737313037464637313238324133453836354145363930324543444537303132463143343643303437434232334143413438354236334341424543373544373734394542383246394638374136463533363331463741414430383733333539413739343730314244364446373633354245374332424645383937314438393038394223290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xc412ef503ec36e901138b7c263f34f77b616c3ec8830d8523b52f98b8dfd7a0263a47df3d61bdc4650a04830634f2da302521b082e68b9152e3d9177ae03f201	1566680026000000	1567284826000000	1629752026000000	1661288026000000	4	0	0	0	0	0	0	0	0	0
\\x7e3be4dfd1a856c119b06e080ab8e7d5334ef8c602dc419ae7b061f7a740e02763a17b5421939caaf46d610154121acafee4a978433ce958432cce2d7166590a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304134433532323745413230464232463831324637394437433833304334353534453643413643443839453835394531453132364543343144363537334630394431333045423738353734313832304346383630383841463744463539353534364235423442364141464232434632443842453735423235424338463236344239303042393146444341393837463243324136384537353245354446314137384137413039433233413032433037343334314439464439363935303631313941423741433233443243413541463034454241454136323336413346304642443245373435384636443130364134353137313836443636383141443141353438363323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xeb4aee0d205934e622df1a37aa31253647528998ab43f44e6f6f78d62ee47e2a81b7a20a90b2f85dd0a188c4580fea2fb3293ce6013262df3cf6d26f9df33607	1569098026000000	1569702826000000	1632170026000000	1663706026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3299a46c38e53942eec65da02437857c5de048e46c7cd2506b9df54b067044f4b68c7799d61b4f68a3832871fc9ef153d65d8a439a72c51713d7a3f5a905c148	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345424442344646304542304330343043334239364334304634393534354635353036324436444237333532363432333043353946433941353438413234343743383744414135374346454646394539343031323331433343313937314246424632333643333339414137383844313341424233443545374534393539423637384244363137444331433943454445373244454434463542383544383036303330423345334334433532414343444143384645334335423833423435314441453832334132424542314233383546453144384644304634413545423241464438463339394231374546313146413945364444413430443933453233303533303123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xbd4927af3866e5d1bd9e7d30aeb5a4c9aa84f68868993f3fed6033a7e642c868c05045b21ae226743f9d8e45917d9ece6e0cd3d802c3b29c2adf48c79617150a	1567284526000000	1567889326000000	1630356526000000	1661892526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f39418d1aea8abd8b19fdda8e8453181221d585dd178c5aadad4ecfa44bcaec439b2dd9c57abee93e7ce6f501c0314a233de5c3b08f60f1b4892f7cf987225f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139343232323436313241334339393438373339423941343545343145323539324633344238423142453144363530313432363733323235443633443733364444353742414633364643323636443645423736424342414346424532353842363439443441354641363344313336324341414641363534424430433643333239414131463437313035324639363534354531313036324633363030353045423037313941394434363244383537324438363532443636433434444334413941383536443830373445463141394541324344364339334231393341383036424645344244364132423439443341373443323330414635304133443239413832414423290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x4abf22c5a719d5e886ecd987ef96e52b017b0734d076119d877da96891119e8558e431348e548c746bf78e6f16bc762872a22cd465835e1066da2e0ef55fb906	1568493526000000	1569098326000000	1631565526000000	1663101526000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0217ab3b057d92de202aaff6489865de103a2875bf8bb208e3827e75da74dbdd7331033db0252dfece52e211d301d763139f14e32926114f5a4be3d4b59e2e55	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303941393935383844303931463445303545343043343834413544434534314336364146313139414130363730433834324545423931334241314646343935413841413539343944424145453730354646453536384434383834433833413633454345374534354335433246324139443543373931374638303535343532364537324138353435314430384545444531333531394142464246453133304335334646393945314232444243463143314236363239334343414336343745373845353738324546444430423030434439333835434242434337343142394230434246434341304430313830374534413939323030433445413345334241323234424223290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x34b2fff44cc3b8e61f74363936457576f9c15645a7da62ad104d808c7919e69a1b7464984f29add4cd9025d4222806e359da481318cb8d275a6e047d22013a09	1567889026000000	1568493826000000	1630961026000000	1662497026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d55235219a1e605ab4ed74ae1de9a893658ce124f15a84bb50c6e80f49a6095fe016543ed02b57d1f4c4ed9688853c21a70c7e003714fd5f1b7bcad01631950	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304344394130464630353831303544313835354337393739394533343346323631464339373130414537384143324235393331364334354133333645303943384630384535354546383942313145374330304642424144353836354542343439343832343935463537424233364537303230354143314442423843444443453542453042453936343934353645333838313842423544314244323839313433323933413832444232314639323541303234444336354344313834374130434331383532343135424430303030373739384131423434383643334646353739314235394245363330393531303746303033313141444633414139314341313537323923290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xe3da132c00933b038f9b634c2b30129f11e7bae5ff93e9dd007d212b331c05429615a597da39dd7a24d103f3bcaf0f1b5de8a74c70746b22103665de91f8970b	1566680026000000	1567284826000000	1629752026000000	1661288026000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xadd0e60e2926deeded8ae878a8846e8985da603b1a112275b7ff64dfa868e79d1a0d67426a2f204de9435007152022c87911db26e2dfe58a56ee5226860afd9d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304541313535443632304442394142444232463041453330374530434543443337314346384146383935413630394645443638333241383839383439313331434431323242413532314335323441314439434643453735424133323146433545333836313935323032454238413835383937353830354636383144343132373730303435433630393046314538433632314331313443364544433631363036373733463832434338354131363235303735363534394131413243333434453231413845433537304537463244333631374438303233323942453938343237323346383446343838334331344539433345333036353236374634394543443531363123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xd174ba251da7de6d91c1108772bd17334b9f1af243067fb9a384e9a13cfbe7ee7ee76df084036bfed34f4e7b875af4e941029c6caa4ead7b4d6617134f9b4b03	1569098026000000	1569702826000000	1632170026000000	1663706026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xe149101f92a1d94ac50c546ab6e78ad1a1273bd10ae476d60f5a009c4ab62b7b57a9cd06c00aa2c95feec3eaf2d58b7fe2efb207433736dbd5c54ec13aef8fe0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304239323642433444383034313239333841454433454137373835344241433345334538384344393846434243373432333732454435453035463942413037393739323843423938383033453231443636413439413842384131334133384530354346333336433438463333323036424444313932464646454639424638464132453238394645453345463430343238364233423836313133423846453641463434413539443445394337413942443837444337374436373142303144384545393134453344354643383231314244314644343342334139373744413637353735384635394134443346453542304246424236384139353233443342433439364423290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x502bd71d15afffcbc026f505c778fe3d8332d7b4759e3f4372b20ea8b2281527c3a13bffe4fe5b32153b5bba085fcac6fb2351fe1e06be5c6a1310ecfc798000	1567284526000000	1567889326000000	1630356526000000	1661892526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x61c6bc9310caa07c1ee56762ba70d13e4e9149ccb7ea768b9b852294459a3817a498fbe10d0c4a72cd1b9265f9c3ac8817414962179022c527ad54c9250e2b77	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333363539313333374633423742344232383430463937423537384337313233443531304144464535344244464634344630434142363737423630393345433642313635314146373733384541393937423346453731434441313430363232453734303930364133393838373833464638464443363432433936314331424338443532343844333945423342363543343335383330463031453745463437353933453033433043434635383438364445334431413434393132333445363934383338343143304337444345463631353234373637323846303733324433454336343831353643343331453331363942393343453546363033333939383446393123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xaa56a37deb45564604f053ade1b498db3e341a8456bd0c0b809c929ef292961574b0dd0d72d7115903a590e346d31d9b6e0b2c83c4bfae8198ecc4484486e106	1568493526000000	1569098326000000	1631565526000000	1663101526000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd7126b4e9a9963582fa0c88a5ea6dea2cfa29b3bdf80ee9163cfa46536eb3f8c9797a782b41c2d0c21590163fd34c88eafa259f664e6b632cd7fca5e1850a843	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303941434345414131343139364233463941334244313845343043343537374446313237313432383943393243303844443645333746343132413945383143434330413446354344353843384534313244383941413135433044314430314638413736463432304631383238463236453131313034433436353242444541354433344332304432443938413930383844414439433244344544353533313736343539383930354334453139353334364432453533303434323732424630434141434445413145343035433030423732354643424332393937354541413034303941413335354642313942393537423830363337384332463344433737314331413523290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x64ee8b3b904dd1f3534160b8f3a048b71d1570f4b8fb93db2e260db0a1a5f4c13d097c320406089d700423a66b4db8252634911d205dbd06732f3a752407620b	1567889026000000	1568493826000000	1630961026000000	1662497026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x07c5fd1e4ca3d2b42adff89d1ac58a3fbf2931c4fff8d7e3df24e9bfba5cdc2d8bdfdbd9455b27834ccbf746baf2f9dae313c99bd2d9505939f60ea1be841f43	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139393537413034313537383639353744443031463134323933453241363835333039414643364333453331323243363732464646304442463645463631463133414433303432393737433442333338343831303035363130443743383744443930393745423735463243443333304334313645443837363742384231463241454235303636394438443532434545384241463945414238364435333430363141383335413243363935374336343031363038423236344638374642344430323743303930324238303336353943374245374132454342393845433437333743354235343943394537423846343231364230453430344131464245413043353723290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x7fa960d488b73c903fd021295b03017cf49e59b03a132ee9531e5333e8e209485bcf4abcb14dd816245631779efc6db543f5530ce424170a0b8e73a1c329b003	1566680026000000	1567284826000000	1629752026000000	1661288026000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xb02330403a8038129442ab0b420453b5ac3d3e37154e11705920fb554cafe14fec96aa93b2dd85cca39e46691250f815ccf9f426dbfb4b3c11b283cc92ff8f55	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304144323035353543374142463744323946464141423146463244433842443731434543314545454641354639424232323237443430453038304239453535463646384542384230463446413545394438444339393039383144374544334630424131323034364246443532323837334542384441344535454543454337434431303942443243304633443739323132444642314537423843334236324439393944354644374336344246453236454341444630434243453438353636324145424546334243423844344237464346444542354436343737334439304132333833394134443530353631303945393631443330383944464237383241433230424423290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x911976d9fe8b4c5d5408f3fc1ccf1495a66e4b7dce0088a603d35ad8bb4464a1e43df3d1e0c836a06bba6a325f7c5d94774a6ed5501ca35897c243e48d72d80a	1569098026000000	1569702826000000	1632170026000000	1663706026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3bf7ab33c6ff5d65846d03d447a0233d7196cd85738b0d94f466f060404cad46e991fa84fbadc16488d64b758e5bb5f56dc47a50fb7c203a6150dffc20cde427	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434353938323436433246444645354333313035343241363631343732364343353632433236334138353734434643443646413131463135333039434630444438464633304544423546333133383138333132433530314544444532334632433837354437324337304345333546313238313845323446323634324631424139364444443942363441364631453142424235303735353235313334433530363838313633314130433042353937373643424433393430443330453839464131413446433145303445353136363634374332333943363139334341383642393230314536313137414246423331443738443239323031413637313139434636393123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xae9ac59cc075c875aea7bc1b76c27083c4878257271b49f4462842a73e2e7f099f0b93ed8487996b3efb98f02fbc312edf8c4f13f74d85d026c3888881005801	1567284526000000	1567889326000000	1630356526000000	1661892526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b7abddcff03f823f8e0c91f06ec48406fbb72f9f2decb89f12cc128f03f0f6e5facbb62aa9bfd909125dbf643db7cfe14ac7dbbe95afbf6158d19c740e51ec9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244323833464243424233333130383337333743333634413031383343343631383836304136413135393835433044324242453031413736313936353639384136463242424142303233443243444530324237444437434336424446303841373744344342464538314134393745423536354137354144463330464231453345443533424633434542453235373941414341414235303530424139454332364146383644363633303236353730464235383439434436343244364236333231353937424436303535384332453945304636374430353833324243413536313343313944363539333644383530413531453538343639323636463539424436434223290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xcc87fc520f9ecc2282e7eb8859b9bcf8a464d43466c640b99cd145613e84906c6af6be0af8fe84de63737e31f8298fccb7a9124777ab978e76b3602f43f3350c	1568493526000000	1569098326000000	1631565526000000	1663101526000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79bc9d8d477fbe41ee5ea89449c897392c4fd51a07a06c41a2d77e8c8442d768cb1f4f787943ba30b3b78b669621953b24309201a86dbc17856a91e2f3dc32e0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304443413333413439343733384435464634333545363839313432443235414441433839433834433437343634313843384546313431343736413545343135424543413446343937353641354541363130363637373643434242333731313130304346314641304630303944343242304542423039453941463632413331353536414333373935303538413437443730333945343346364636443730433636354538423446334142324637373443433042444434363231333245364434313445314530334439354336383534353638423733323039334545303836413535313634464344454241324330303642314434354131453032463043433644394341323323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xa7186629c3760443e3867a15708bbb243ee6063fc6bef23ed584ad4869967f43ed56db0bb6b6345bc42338434243dc87ae28ace6ebb5bbd390cca230c73fb10d	1567889026000000	1568493826000000	1630961026000000	1662497026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9ed70846bf1d5e7e449f7ccd6faec8e5b52a42b1e7932f070602daf016540773a753e5bf7d155ccad3b42abb53941e59a65838f6e872e38547239bc9afcc0d3e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304231323444454635444133323733393639333845393837433834443745373446374241324643374344343046323231453241323235463539443530453839324233434442424330303333384637454437424134323246363744423041354546343745304633323834384435324536434245443343303434393036314335303643413043313530433644463439353630424341434243344343343131394534344444453033383130314536443645424543444234374537373732303434453632354646333137393039323931443643313846323533384630454641313744353839324246313443423444424543323441374541334446374635304644354337414423290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xe49a19ebf25919485de4f291798ada16714f51c4c97de0e0e71d7a6efd024c5f6d47a942da85b2b7a7db65aa3cb05f7c2ce44c570452dc17eaad1e291cf58d0f	1566680026000000	1567284826000000	1629752026000000	1661288026000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xac62b8a8c2c77a0003f00ac92439730862236b1a3905f6198c5d77fb6abcf6012bc103bf42321023f449e3c3b9f9149e898be220e7da580ec934c9d9f14c5680	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304346354343333037424142423739324441464241394138343044313634443345413944393832364432424442373836324435323042393844424136324343304238323046383931343137344243463933323641414241453746324642443643323742324335424630463541323530454432353343433435364533463843303838344637463344423638324330454131343133334235363645383134374341413045303030343146443734433939424346303833343735334444444536463037313335303636433241363641373639333841413741314632313432384337314544464239444339433345384342363732373230313241333845433642303130324223290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x1bc2df0a344f8d5e23bff58462820edad5665759ecdc42142087d97302c86bfa2fe590cf31a4d533ad8b745205dfc46cad7f44b2ad0666a445b0059a3b90a20d	1569098026000000	1569702826000000	1632170026000000	1663706026000000	2	0	0	0	0	0	0	0	0	0
\\x5a7baec0f64ecc8a8b599e8e1a38a6c6374b80ae72efe86d4d4a8d5735714be17b35586ce30e8953259fa723792bee35506bcdb7d4c8d9680c190656a43877e3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304437444531324439443231343732433444383843384531383735343439383332323234433837384641354444434136433430423644313538374634443044383633343742423042353132303931413939304234363937413830413339303731373634364342314644414437434443324544334430424138323146454132424333463243373242443836383631394541413931333839343241324245413644413233323437333744353538373732333938313134333832304237353834414436464333414339453337423446334533324634463630423535303444463637464337323435313633333645363930454532303345464242424631433235393732414423290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x76192f119a6976d9c5b3297045f8c0e4f31623e6cc151d5e529d2bb92ac5e4cd678537cbc61a06e58d5e9ed8e7a1d6f297a8a0eec9256f7d71385d49f692e808	1567284526000000	1567889326000000	1630356526000000	1661892526000000	2	0	0	0	0	0	0	0	0	0
\\xf1e047f433ff43647b3fd58fac6099f8c53d817d4081beaf080131af64d9df40b289e2dd455b601fdb4ad85e14598d2d99ef1d075241c9cfafa52c9400cc8ccb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334333630313634393234323339423132463038373235413336323038334337433433304342323032393637453130374431444541304339444233464441383144434238414630363934423346324245364642333445414542373937414534463238384546423732373243393831373339413234354630463945373334443233463744323438304344464441363732424546384338393532313639304146323132303330414343444337413030434539383431413737333339324243433442423739394639374534413634434537453636354142334243303930314345363445413839323838453633444137433844463235423733324532373434374337433323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x2160bf294ae6bc39e6f1188ae67268eda0db78a0f2d7fbee0fbabefb8a8d5a99e68583019df6a2b901defffc6b158fd19b6df6fed4b60746570c439bd2263502	1568493526000000	1569098326000000	1631565526000000	1663101526000000	2	0	0	0	0	0	0	0	0	0
\\xeecf9757b62f371882a78dbd05c9cd66d0e7a83d76d979dd53f39157dbec83a209baa9458785e5849009f6b62b9b57ebb93463f66eb500f523d3fc23d677b14a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304337323531323838344439304435413944373638323431394646423239303532334437363143374331393942423937383839303945373943383737413145434539313837324633354342373331453145394631384541323433383141463543353430423535364238393446383846333845303539334445464136343636394142383044374331453545413235384143414231333243424246443033413731333738314632463032444444433335424331434431343338423334434241433332423345313045304337334332444641413246444438303533333142443843304546344542364244323735434637464642334434413032374139463137303046463723290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x1e4e7925ddb706bf8f7a9ed10d88314375542a2f79dae824e25d832027d81368a199bfce0979ab871c66f41a3064847df6e2805571e10a7565a61ae1db411b01	1567889026000000	1568493826000000	1630961026000000	1662497026000000	2	0	0	0	0	0	0	0	0	0
\\x811b20bfe69e30ce25db3be099936103c9a76f9602e38ac8e6616732d313ee4ee7e82e4283cb6902717ce95eecf823ef966f0c33f8238a8853002fb9f7cc9364	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143384342454238363341344245323334334232343731373046353331343834374331423843444130464434373632343933433832423242384337343446414442363641324535353332303642304443393736333335414343464544363542394541443432383646344533374135393942434137423838333643303235353130344336363643373033374531434331353142443136424641453833413433443432383234414344414546393539434335363843413430384235334430454630373335413942374539463944394142373746444530304334464230463441424339333837424535444146424444424633414334334245393844373946313444334623290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x802896a2e573bb75da46cd3db3564b2c1a79395c5f555217a3852cdf90bce6aeeddef6893fb2fdf6289784707468026cbc23dc736fdc92f0d4f84d7147d43400	1566680026000000	1567284826000000	1629752026000000	1661288026000000	2	0	0	0	0	0	0	0	0	0
\\xcc0b7ce4bebde66e9ce47e16e30a8036d6f63e6e0a2595f4a140ddf051cdc9b53663b53bdd057b102ea92131f65b2900e8fb83942d05db336cc5ad9875408079	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436383832443635323241394543413738393039413941374646383344414135304631303130453844423946444138344244463243434336443937353436393731384130364434363732453536394539414339304531393445453032343535464232333530383843363632444431354644384230423537303833354438463642443841364539374631333332463443354446363346464646333544303037394146303039393543303030393046314635393330444138463943463843344235364435413133454139384445384333374334394232364536303730304437463342373733413742384244363334334146433734413637304346383837433737453923290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x1d339ff95c0b4a52403207a847afb5af7820a9207c29acf64511077735aafe77a43051f64aaf3c4dbd493c55f0a67883df74e2d2ba3cdbda1adac01f03d3030f	1569098026000000	1569702826000000	1632170026000000	1663706026000000	1	0	0	0	0	0	0	0	0	0
\\xb3ee20426a17a4a62171ed483052ebc40abb3aae042455d8fb3afe6dd7a327f4351548e40d514e87417508cdb13827b893be732b4ad480759e81c9b75d16f3d7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338303743373843384238463832354244423439464435353245313844413245423735463838313442334138453538353844434237384333463241383931323742343739363546444530323837453633353630363534393630463636453843454643354131333233433144313141444333384638454637453331394435373146314133423045314646313143384138394237333732324130334237323130454644363146363943333237453446333538354432383333414645443441313843304135443444304441383743464134424539463435433743314537423345343532424341464141323534393345373444334441363642413237303837313337363723290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xb178724a0eb0986230f8907a50632cd2428de13fb4e630b084105186659c0876ec39529b0fe26e7c14d56cd938027d98bc6d0aeb44106b92aa1d30f67d7f430a	1567284526000000	1567889326000000	1630356526000000	1661892526000000	1	0	0	0	0	0	0	0	0	0
\\xe1ee74af47bf7a426d3e336a5f6c5478e7028eeb29aeb5b860a90b9fd7def36a0e88d885c3484c45fce0293994952dfda6e18dbac387d85f5353a1b37a21f384	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342353937383236464139383542393443434530383332303141303439353438314546433336443239313639433538313032373430344232373946443737454537344445303945433831324137313238394533423234303945384641373931434435353237354138423434344238443033373736304135423135333133304530364142344436424139313138324643353232314330463144464433423331363935444434443344313545323941413634323631353234413933414330374133304531364445333942353446303336384436374246413431334534373437393634313946353241333035333538383136373038413432413941424431364146333323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x25c26e4fd1c7a6173a9162381dc0b795b90c73670e58ba3515d2369da89507c02e465a1bbff9d5fad4dbd33e438b5f55b006439c9b94d45faa1f94f0ed35da0a	1568493526000000	1569098326000000	1631565526000000	1663101526000000	1	0	0	0	0	0	0	0	0	0
\\xc7a8212aece47cdc45ac7379c11feeb33b910360c461a83c4035bf42ed5ebd71db31ef0c424602679721c6fbf6976a978c2c3b5fa5e75f429a24493af55e5170	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304441424231413838343032343631354544434339414442323435303735363039373834344132374238463942343437313441353345373732373045384643333741323031453145323635363338393539343444373641343133353831384643324233373733383337394234454642373141384235393942323232333934364536414632333543443043343539413045314331304532353446353945363638303042323430344334324330323833333739413031323542363834384635443138424534443331454134324530353746423843443641314139363639323845333635383643454146334338444336394339374141354233414143383441364436423323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x7f82250e34f6abadbabac514a890f9dce8713675f92e4d6bd381de0635221c23537553a2c5be6e570ad221441d9daf97873d16717a24398de2166fdbb57bf10a	1567889026000000	1568493826000000	1630961026000000	1662497026000000	1	0	0	0	0	0	0	0	0	0
\\x2eaaf8f209e9fb30f6dee5c15b5477fa75b829fe0afe5229241590bc43fcf400e8f21d66484ce608817ea7d59a204a875c287dcea65feecfd5e550fa6aef9cc0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345414635393944373939344436353743343030373139423944354342454239463138364331373134343843384139363135433031433145344630463233363542324638433631394441333335334142324237304341423438433339313443373644314646314244344345334234443933444137444135424436364143393739364141364436463639453539363641433938443734363431443431444336463042364636413130333639393333343331333246443738384541463838373834383546413537363839303637453730383730373839423631383343344637344241453339323343384531444438433736344433413144333946424339343839333323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x5efbb68950789b8a0179000f6125474bf2524726461e3a394e8783775fa1c0bbda93f6d0702969cc233d85037d35687a58119b6473419be5dd2984ee0df76802	1566680026000000	1567284826000000	1629752026000000	1661288026000000	1	0	0	0	0	0	0	0	0	0
\\x293c4e81abd47824b475ffc57b3f46f0d77399859c57ee0a7a94ddd1f97874c4bfd0917ded2463c29a65f544504ec933a8e98cc13b6f29c9627f31a2458bf723	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304437313832313333363138413438353344463441363331373130413632453739373134373243453235353646434336453845424239354346453639344532454445424131334438303139373837314546343431353131353346444130304139324446334232464538323343363934414443303236384639393932313738333932364134354433353633333037394530463032383230443739324433364531373731383442363044463932343942304138393334354136353534453339454343463645373335314443373637454532423534423138453843393146353844373746363745343943433737384639344439464432314136314245413031354132323923290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x2d183b7a00977c427bf8f15c56fd012c6c4105b254765396a9f72ec3b092de681321aac256ed17bca9b4b20157bc57a1ade703bb7b8ac28c4f146b84ac6f2c06	1569098026000000	1569702826000000	1632170026000000	1663706026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaacc526dc1958a857ef52630bd5c07ef050b00ef4b152fcf6313e2ffb6b32e4a531a79a980b3b233ba5ded9cbb5f29752638f291890a3b63a5b23899ef4b9d96	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243433834343232373334413431384430433739334443394342303939423344334233393132344445434534313637413431444534413737453534323734443831353346334130313343464331314331453042333234373342464431424133443531424232353837344446434346323030444335324631433736463538303431313433413232343446383638373239364239314337304142353044394544333531413938304432433936363039303630393030353733364242373631463833443330433137344134303537424534384630464133384239353942423237453736463131424438354241363443333833383146413235393844383339354543303323290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xab9635b3a65004849bdcdbe1542bb73068ad2d4bcb60f380005545a7bd1cf7e8e9818155508247f0bdb098def82bcd8afe9a960b35c42049084c67e4bee7100e	1567284526000000	1567889326000000	1630356526000000	1661892526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b9012724b31bf19bd4c3e928cbb6f179e9ed04d6622a35926302c006e02b270585df18d7cca89b4896e63283b2e4b3a74ec8567be3877fe263245feb43643dc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242433934313831423045383037364236453541463534323831334531433836363545453130343346464441364331383435334642443531464642434146344536304232353339353244343532463934393636354334394344333433383044413338413437373137394134364538394341453842333734354445353339453736334446363541453844423033343446303135464442394239424433354236364143303038313245383032383144433138443746353039413531333636413946343743353633333630314235443633333746363744434243303633453934433346433946313036354441453237443239353742333236333842323445463246393123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\x37f0273e61f554422442f0a264ac100dde995a4b0f48dd27e2b0212367ed357c944fb75b9ab511417c42ab3209e4c00814f223e4fb8a61dcbf8956ddf54fb402	1568493526000000	1569098326000000	1631565526000000	1663101526000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xee30629e1663541f498d4fa2331c8f7544911cd036dbb5ed1db9fd7a671adcbd990678f52d47b41e3ed83758d1ea8b244d6be39034224e96f7717f9780ae0815	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304535303530373534413337424639414235333834384130414431414541363032374641413935393137344336453143374334353734343135454537303442334641434639363335454330383843443144343143413032453430434636414637343036304639394631303339364539463633333844323930364641343839384438303645333033343546383033324233373338354639374641313435353244433030464530333333464632304336393438334331413446343246373338333837353533324137324237333942454233354243383745444143334631453133463334393043373644324245433135333338354243343235324632394631343838463523290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xb327ae1e27d28ff338378edd5e9984615fc3f2acb42954a164f553e8984a81dfca8632b817b397032117e001a74249776e184bacf69e4dea449ff98e347cb305	1567889026000000	1568493826000000	1630961026000000	1662497026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6953fa324f793b3d36c556f214d946304a1a6e870c475d3b5c27b3e6afbb853c789b52e0ad6cd454d76b996863a47d8a47548e99f2e0d2d0d59419256a3ced58	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304531363833343935463343444144343235363436423535423541454541424233393231393539414442383032414434464238394543313346384345434133393132394330443735384544393942323632333242313242323033354145313245313741453945433431463633423043444546343139373338333036353041334630303546333933373638423439414637344435463736433232383035353344354130314635304135313936433435313831413832353242454132314144334137394638374437414630393842393842384538453832443238394642463037433736454330363543353234464444324137444434334430304144354341323039453123290a20202865202330313030303123290a2020290a20290a	\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xb93b3f6e5ee0f01384dce73838f208ffb7acb46cb04f9308772da482cae62cfb9f7cb4c447c149012c44bb806fa66dc4b72219616d4f65db3de1780c773b650b	1566680026000000	1567284826000000	1629752026000000	1661288026000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\x82aaf02d2d3f87cd7c9e3f8cd37ef46916d35d9df64be733b5b2755d8701f63a	2	0	1566680065000000	0	1568494465000000	\\xa94e75b53fe827ad5d3b2992692f5b35f29d95e4c6b022ed9015106a92992bf6	\\x3b4d0397dc388b17038c7d89a778f332957821c2fd9c4fe881c5aba6729f312df417f934be667d90e56abc4457b518ba071cf2c9b24b9ed5b4f6e952e9bdcacd	\\xcd4f855bd939986f46286338f878bac3bf9ef611ee4f0f7d71133a192e65a98778ed0e180c598775f7c2d0a179b0fc1851762ae06d5ce93d2d6657508c1d2ac3	\\x4d06d6e61f5cb9d8a1a4190244aa8ebb498d824fd6f0fec8e9794400ac9345ebab3cb45ad8a10388a977b36a4e9dcd7086123a06d8f32da4b81de1a21f38a006	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"YH6KPCSNXWG40M6WP6YRNBE5QY7SJB55F6WZ1MA3QB4XQXXTH1E5GE2S0MEC93D5M55G8TYHZ8KM43FFV61RDBF1J00KY3GYV0H5JDG"}	f	f
2	\\xe3b1d487f35f8c68173e5ba575d1a3c4bdbc85e67d57eb792b1dc62de93a0932	3	0	1566680065000000	0	1568494465000000	\\xa94e75b53fe827ad5d3b2992692f5b35f29d95e4c6b022ed9015106a92992bf6	\\x3b4d0397dc388b17038c7d89a778f332957821c2fd9c4fe881c5aba6729f312df417f934be667d90e56abc4457b518ba071cf2c9b24b9ed5b4f6e952e9bdcacd	\\xcd4f855bd939986f46286338f878bac3bf9ef611ee4f0f7d71133a192e65a98778ed0e180c598775f7c2d0a179b0fc1851762ae06d5ce93d2d6657508c1d2ac3	\\xcd01a470b0ae9acd6d08aef59c564355eefcc5357f43e8cb9e32730e2e391d0d069a1832b68c4a58863ed5d78710f2e2e62b3dddd8288e7f880cd1e6874cac05	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"YH6KPCSNXWG40M6WP6YRNBE5QY7SJB55F6WZ1MA3QB4XQXXTH1E5GE2S0MEC93D5M55G8TYHZ8KM43FFV61RDBF1J00KY3GYV0H5JDG"}	f	f
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
1	contenttypes	0001_initial	2019-08-24 22:54:14.548137+02
2	auth	0001_initial	2019-08-24 22:54:15.405741+02
3	app	0001_initial	2019-08-24 22:54:16.165228+02
4	app	0002_bankaccount_amount	2019-08-24 22:54:16.174517+02
5	app	0003_auto_20171030_1346	2019-08-24 22:54:16.18504+02
6	app	0004_auto_20171030_1428	2019-08-24 22:54:16.19663+02
7	app	0005_remove_banktransaction_currency	2019-08-24 22:54:16.207901+02
8	app	0006_auto_20171031_0823	2019-08-24 22:54:16.218955+02
9	app	0007_auto_20171031_0906	2019-08-24 22:54:16.230111+02
10	app	0008_auto_20171031_0938	2019-08-24 22:54:16.241311+02
11	app	0009_auto_20171120_1642	2019-08-24 22:54:16.252282+02
12	app	0010_banktransaction_cancelled	2019-08-24 22:54:16.263219+02
13	app	0011_banktransaction_reimburses	2019-08-24 22:54:16.274544+02
14	app	0012_auto_20171212_1540	2019-08-24 22:54:16.285683+02
15	app	0013_remove_banktransaction_reimburses	2019-08-24 22:54:16.296784+02
16	contenttypes	0002_remove_content_type_name	2019-08-24 22:54:16.351386+02
17	auth	0002_alter_permission_name_max_length	2019-08-24 22:54:16.374338+02
18	auth	0003_alter_user_email_max_length	2019-08-24 22:54:16.463627+02
19	auth	0004_alter_user_username_opts	2019-08-24 22:54:16.523067+02
20	auth	0005_alter_user_last_login_null	2019-08-24 22:54:16.585826+02
21	auth	0006_require_contenttypes_0002	2019-08-24 22:54:16.608392+02
22	auth	0007_alter_validators_add_error_messages	2019-08-24 22:54:16.668564+02
23	auth	0008_alter_user_username_max_length	2019-08-24 22:54:16.808434+02
24	sessions	0001_initial	2019-08-24 22:54:17.120078+02
25	app	0001_squashed_0013_remove_banktransaction_reimburses	2019-08-24 22:54:17.157031+02
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
\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xaa8fc820af2dae5842f99c446ceca2a45bea02b7465f8eed11c1fdc9412d36bda9ebea81b891a186dd980c7f32b7f0dc61afb097f97656727ba7f129eb83f905
\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xbf11601b1280c543a5dbe347c93e40bb773e88fdccde2b2683c6892eaa68713deabce2eb73f5e1e58134cd336d1e68f641454f15036555ed1d73bd1df6e78902
\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x1b1296e1752eaf84d410112f3bf137c79f2a2a05c70281133a082b3c7132631f984a2e301a861787a113065a0c5b661088024cacf94a0a49637aa979e8a1540f
\\xe45ce374b04eb9b69d721c88ad9c7e810d3a881bc0db4b55a792aeb5cdd131e8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xeb68d3fe92b0a5a55eb731f1a53f49eb6168eaa5d8536e0f48cf685816456783adc3211e20c9a0aa019dff81e3a19da37553981826c0aa4b16ff0124e78a870c
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x82aaf02d2d3f87cd7c9e3f8cd37ef46916d35d9df64be733b5b2755d8701f63a	\\x811b20bfe69e30ce25db3be099936103c9a76f9602e38ac8e6616732d313ee4ee7e82e4283cb6902717ce95eecf823ef966f0c33f8238a8853002fb9f7cc9364	\\x287369672d76616c200a2028727361200a2020287320233136453044383145464643334335344445333432423942373445314136413144313543343842433437413230453044373837464242433839383031314535394443343735303838313839433737373230453936433131413645443334333036333732324544304237383436323838384236413830373846433731444430323934443538423644313945324443344638303834444435334632424237333544353732334633454330324135413636414631353538394132363637453536463441313135314242333739363542323230433431423044453331353536394135323337463234423643444234373333334245453339443637423336323942454541433523290a2020290a20290a
\\xe3b1d487f35f8c68173e5ba575d1a3c4bdbc85e67d57eb792b1dc62de93a0932	\\x1143dce93317f2e1526feef87fbbc95a748df208a2078ca3ec55743a782d63e36456538d89ab84f097b6bde0cca9835e0c8f4aeb2658fe8b0d713473f806e688	\\x287369672d76616c200a2028727361200a2020287320233237303545414236414636333437463833453246464642383334323636423336393833423838393342304234393334394530363231453631344643393536423631374244383834393337323337303343394141433837393546313938363638443933313735443241363637434135423232393334443441433434393338423638443439383139413431424532343245313437363545314637453830464333344637373038353036373731324342343544344139344643433832424233394437343139374243334646394338453930423145363030463245303332343536433345414345394434443931344333303536303839424246344630323641393344454123290a2020290a20290a
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
2019.236.22.54.25-02W3KN6XVGEEM	\\xa94e75b53fe827ad5d3b2992692f5b35f29d95e4c6b022ed9015106a92992bf6	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233362e32322e35342e32352d303257334b4e3658564745454d222c2274696d657374616d70223a222f446174652831353636363830303635292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636373636343635292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225748454536583547395457564437424a334a3441563733594734364b4e3230565233444d504e44374a415142424b454836374d30227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22534e3752415059533736433659484838434357464759355452455a535858474858533747595a4248324358314a424b354e36335148563845333036354b31564e595a31443138425350335931474d42503542473654513739374d5050434e54474847454a4e4752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224e3537374244395a58304b5454513956353639364a42545636515339563546345254523235564347324d38364e344d5335465630222c226e6f6e6365223a22515751574350315251424b4754324d514553383132524a3453385030534b33434b4a504e594a593234525436364652504a374430227d	\\x3b4d0397dc388b17038c7d89a778f332957821c2fd9c4fe881c5aba6729f312df417f934be667d90e56abc4457b518ba071cf2c9b24b9ed5b4f6e952e9bdcacd	1566680065000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x3b4d0397dc388b17038c7d89a778f332957821c2fd9c4fe881c5aba6729f312df417f934be667d90e56abc4457b518ba071cf2c9b24b9ed5b4f6e952e9bdcacd	\\xa94e75b53fe827ad5d3b2992692f5b35f29d95e4c6b022ed9015106a92992bf6	\\x82aaf02d2d3f87cd7c9e3f8cd37ef46916d35d9df64be733b5b2755d8701f63a	http://localhost:8081/	2	0	0	0	0	0	0	1000000	\\x2d0281c8d82515cb9c20a4c1fe58265ffb451c83053c7776117ab802bda8ac08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225950574550485147594e324339354e5959484e37394b3034345347345a4b43583445524145475252314b45414d3145474731583847534b414e383132513739314146524e374835435732414a34465854444a434637464a4251345659395147374e484642523238222c22707562223a22354d3138334a3652344d4157513731304d4b305a57503136425a584d41373433304d59374558474846415730354644384e473430227d
\\x3b4d0397dc388b17038c7d89a778f332957821c2fd9c4fe881c5aba6729f312df417f934be667d90e56abc4457b518ba071cf2c9b24b9ed5b4f6e952e9bdcacd	\\xa94e75b53fe827ad5d3b2992692f5b35f29d95e4c6b022ed9015106a92992bf6	\\xe3b1d487f35f8c68173e5ba575d1a3c4bdbc85e67d57eb792b1dc62de93a0932	http://localhost:8081/	3	0	0	0	0	0	0	1000000	\\x2d0281c8d82515cb9c20a4c1fe58265ffb451c83053c7776117ab802bda8ac08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22564a484a4753394e50484346385a47544b4a4137514552564a4a43474d59524751324532353648484232385743424637563332374357534a374d3030423459595944534632334b3244445a4b334e544e4a4a3543414a345631414a444a3652423048485a523338222c22707562223a22354d3138334a3652344d4157513731304d4b305a57503136425a584d41373433304d59374558474846415730354644384e473430227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.236.22.54.25-02W3KN6XVGEEM	\\xa94e75b53fe827ad5d3b2992692f5b35f29d95e4c6b022ed9015106a92992bf6	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233362e32322e35342e32352d303257334b4e3658564745454d222c2274696d657374616d70223a222f446174652831353636363830303635292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636373636343635292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225748454536583547395457564437424a334a3441563733594734364b4e3230565233444d504e44374a415142424b454836374d30227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22534e3752415059533736433659484838434357464759355452455a535858474858533747595a4248324358314a424b354e36335148563845333036354b31564e595a31443138425350335931474d42503542473654513739374d5050434e54474847454a4e4752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224e3537374244395a58304b5454513956353639364a42545636515339563546345254523235564347324d38364e344d5335465630227d	1566680065000000
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
\\x40d4e1b35114de607c1cf2e1cca21d84362fab2e5c7473f573bf564381972bb1	payto://x-taler-bank/localhost:8082/9	0	0	1569099262000000	1787432065000000
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
1	\\x40d4e1b35114de607c1cf2e1cca21d84362fab2e5c7473f573bf564381972bb1	\\x0000000000000003	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1566680062000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xde57ff150add2bea11ee6ecb5acdfbafc490cbcf80e230b9e5e469fcf9fc9a7414596e501736da7ce564299b201ca94fe6c5601ab270b387b6ef8f2c789ac3e2	\\x811b20bfe69e30ce25db3be099936103c9a76f9602e38ac8e6616732d313ee4ee7e82e4283cb6902717ce95eecf823ef966f0c33f8238a8853002fb9f7cc9364	\\x287369672d76616c200a2028727361200a2020287320234142463336303939343646383932333338353146394437354337383436423233353744364535374345434444373031314636443743463342313533374230394531423332394439443641454143303133353139333044323943324344464235443931324541413730354641444338443441373735303546454136393042433033323531373334334139314442393342464436434230443231343032363732434644303834414136363830303042454233453535333042423939354134384642453745464536373242323730373032323137464641434238324642323031444243324134333344353637344143463243443142423833313346434342363637393423290a2020290a20290a	\\x40d4e1b35114de607c1cf2e1cca21d84362fab2e5c7473f573bf564381972bb1	\\x15a93d5c7c05159dc44ac51baea2e13d236cd3fda7a653e0e34438610b4f76f32291ad9976507a7280265a319389bb388dc91187eb643068c5132439fa3aef00	1566680065000000	2	0
2	\\x41df27ba5f2d41423fca10b29e26cf4dad0baffdf0fe71350c64e2f57b2675e2c7d7e559f0bf2b380063c4b5229d0573d6e1505aa535e0deef29a874ac43d48a	\\x1143dce93317f2e1526feef87fbbc95a748df208a2078ca3ec55743a782d63e36456538d89ab84f097b6bde0cca9835e0c8f4aeb2658fe8b0d713473f806e688	\\x287369672d76616c200a2028727361200a2020287320233742303830453234424445314333304535334242394246353745393637373531393935383432323944414643354134323741353135323534353843343931363734394630423831364344304646353745303931444444443936313733453631364634463336413244424441444637433934374642393737333945373645443634434434313431384334313934353132443537393246443046323441454237423437354538303933343241334635373841423438463537344130304645453130364645344336453534373139383139353835393246393033463134344231453430393041424243453331413437423836423744303538394634313033323845324223290a2020290a20290a	\\x40d4e1b35114de607c1cf2e1cca21d84362fab2e5c7473f573bf564381972bb1	\\xf6bd34e77f1ade61c394284922e62e784edc8d534c5f48a650d9a2c87b76e5059da3f42fff08cd36cc2b7d925c9edcbab9315163ad696a7e13806c2b0a392a04	1566680065000000	8	0
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
-- Data for Name: wire_auditor_account_progress; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_auditor_account_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_auditor_progress (master_pub, last_timestamp) FROM stdin;
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
-- Name: wire_auditor_account_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_auditor_account_progress
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

