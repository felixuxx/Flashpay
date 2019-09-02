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
    denom_loss_val bigint NOT NULL,
    denom_loss_frac integer NOT NULL,
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
1	Benevolent donation for 'Survey'	2019-09-02 07:23:11.660476+02	8	1	TESTKUDOS:10000000.00	f
2	Joining bonus	2019-09-02 07:23:19.381374+02	9	1	TESTKUDOS:100.00	f
3	X8FJGXBMAV4CE8RF0YWESG0B8B700GDG110QMQE0DYPFSGM70WKG	2019-09-02 07:23:19.483417+02	2	9	TESTKUDOS:10.00	f
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x924d85e4c9a586936fdda227aac01b496e01a0b0c4aeac5b4be7e2995281aaf55900b22f012aa2e15e5e0741e3c66a158522a8c54441ad574f0667e4b4da791d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x666744f1f0b37bf2794e4ad557d225fd67a72061385b55c56b325d8ddc773d35f0d62abfe736089bf6c97034e1e83e248a771c569584495311abcf52f4bd3e87	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48b5dd6326a9e486d2cfebfbf360b1c5fe4fd134a45c71c7be74cf35a77ca268e99fd2bd20044a9e8f8d8f4925f67990942b25e77bcd3d69e32e19237a2eb6af	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6d141fa0ff3fc51cefc299f475f8c90662a2d0a0b01b5543f3502765d6e358fc0624c887631ef45e3c96348275abf0c30dbb0d1b37989fc03770b3c7f8e19c1	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e74d7ea15f865d266b7e9701f7975e987e548abce526e7282b216db42faf930500256582df74fe711959fdab59b877a6e77456eaf12a824f006510ee7eb4176	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71d2eff05b42c2ca9ace49d02792c84a792acf217af95917c939fe5e9bbe89257198ba5c13906abcdd31a203d07b5c8b40c0e969fe95d42aa58317711a5edaf3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe607c250fae0cf02f68b5565e12b2d8a64ceff4913299eff6ceef10195f399dda6044dff66450297f1f685a0801c632dec96ea0d330722b416f151887f418467	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x11efe64a4061599e86f3f21c5aa31ffdb28621aebe693391b319e0ccf550f80ffa5fb748aaed26c9dc9036ef55c225bd261339a46ba56086f629a524e9dc9948	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x224ea3f51bd1dbbf82a5a2e07d3c139b283c2bfe90acbae78d2f1ce7517d7bd6586891b1348fbbb546e7ecf3fe6848104a1e77828d85ba5238d0bb4cd6432eef	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x604c984017f87a5ac9d920d400cf3ef2161dfdc80f35179c9e1f2e667a435aa633471f91f3be096a745cf73e5e4a00c199ea97eb0f4fb80a81f1dda425600e1d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2142f246ed6041b30c72941acf99afc970c5822b34e1dc3c4daf553438251855ff746254238f8f77b027a8c69bb9506bf18a460dae39ce8a5ed01a3d21f0d580	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x802b9d00aec40a1409c50e401b90380ab00b988631c004f20a056e036c4d480fcd0791be3794febaeee579946080dafb50a29d1ae796885bf262eef838c25536	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf86bf45e6cb32271aade78c66f8a087b667f4777419c746e1e36009e57b5b2b085875379d958c4e8563660c36435ae12407d6df214f37a045142fa9ed5651c32	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22c510d76c7574128063230d918cb2c501d913eb1befdaaea008f0e218f024542a941f9e6637d3bfb73a120cf50b6589d1ee112611f8ed5ee8912288c2ce0490	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0598e8675d36620be457f2899f5f9d629366b82e257cd43e27382139cd6834628f6e6261cb0601313108cd387f1ab667dd269cad7eab169af08c025ef5b9495f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe886224d98612a37066363139e53ff349d6d6f91b5050218b10990777727c0dc19a63ab63e02be91fcc05d542fa77cbb9ab1333aae777f440c2bb26005559a5a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a4f8214c34552f12ffb7a1232023447c03f86754b887dbabacff061bec76c39f1576fcb5713ddacf7ca75069d0214da2538a4b194cfca8be8e426cbf875282e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30503fb92d7711d68bf605402b92bbbd6f9a343cfdc3602f4951ca4ec64bb5d086c5b15f4ad6ad3e19933e83b075f99447255b1dbf4b870b2c2fca42ff596f5b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17e6ced758122a1bcac23f858c7cc28cfaf0cf395951801deebccd0cbd0dedbab3ec8a94479b59aa98200f32dccf06f67afda3dd811522b23d4a66763798f6fb	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3193fdb8b8b1d25af9668c64e80ef0abf739ab93e99a31f1deb1992d9cb87b927d80ea1187419c0f3d0aed13fe106b2eafa8433c31c148b3d340bd0087dd626d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x47a4ddeb9799a984b64be4a9028ccb36c5de269adfbe714dbb21254ff7d420872a6b791d55e1ffb18d1d93c750a60a2d9a16de992b71163f87b437a5c92cd988	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x416689127f5438e3ecbf46458186744155e3fb595061073e2322fb4f94747a7f63e78e3f947141ed20c2e7eaf607a3c65affc675d419d955159a1a713fe9e77e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa0d4cf9630e4aafa0c8fc465ce44ca4cf7fd04448aa615333854ca17898344cb8607b60b1ec05b78c94c2bb3598d7278a95e87abb133e5c82f4dce40a0eff38a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6929f479b6c0058551f4291cd221ca86dad23b7be7e9fe750f887d899da00b2498806037a178e92b8ee1a1cc29b4cce24d63f961aa2fe0460be3a982a4a120d0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b6ea7f04b90776e389b91985d556392c79ff22a264b9c6badf040e63a1e38a82df150fb51cc5c5a8a10da1b16f30f17003eba9da36498f4dbc5c13746ad2ce0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa43c6c89939002fdb520aa27e856dbcdb643453d9cfcefee6af84253c263768290258719074425af5197b573a822704c6977ef075a01aae982698078834d010a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4ef62dd525fc4cb31fc984066065510401a5a3f1fbcb9902983e31e410256a05ec9870f7f71347a7877d6b24d2394787e165739d877f655f08714ac055c3aeb9	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x604420593138620d7125750883a66439549fe87e4017adfb93fde1ef8302cfe6a32e0f39a0aca87b62091d76e12d01933cd648cc71ed9af9dd0baccc20f2ecfd	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7d211020331b562c263f4bdd8171e41279caa565746751c14830887039d7d7e33443de727af5e3b124fb41d35caee541d7f230f001edeb9751178dca595aa87	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c3513f126128f16354cb1fcbdf2c989dab21c1edf402059f18aa70f7291051915afa4334e5444cc9e200202013c82348640a0916235524a86a544a15edeb750	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x29f676708259fb2a0c579fb29e678a0582d84fe0792b8c0712f6a7e7df5508fac7cf5569adc68379ed2be3a0fbdb7306b9e26ac7f53e02fa50253b1a1f062f78	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde59a06268c51a5132cf553a7b12658a1003dd72fe4ef4d1b023eaf79bbf5372116cd99150d21c31a6b781b84b4d33b9a615a49be91bb3a671c25d902b9705c8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b81d5d9394a9757be194b221cb90c3b8a4d7745fdeafc3441f524d75235da5d30442b981bc26d67146048a63b60ce9fbe6f66e127da9e1baeebdae984a37999	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a5aac29a01f36746f2baa61c818aace568f453ccdd4cf13442b4e94b9a1f6e7f151a22e0ac4b112517c553981a39e114551ceb2e4408e75262b31fff2f1b7f0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf7f48a4b6feb0e953c570197fb05086c99536fc12891f5f58128952ae3bae18f68b8d8bca88cb447812931216dc733d31f89fd4e4772e0250750ce4b92054fd9	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa2ec7f7a6fc36923a21359b15e84dfa482c7992756fc6b91a611e31b871d982eed261c4e21c76a6004b922ff881df1ed83e69481a4220d37a3a8608a0603e7de	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x58f1754099672eb64f263753ceddadc6c3ea9e01834fd0a51b065d96ffc1cf8806367c3bd4a0ee1aae221b05fff7d306cedd98abbc314222d4f0919565f523b3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7a4eed6bf57300c29569cc6c9e7b483a3bbb53357be210e0e6c7fd7be47ab5623d12b8c93e413dc1b1674e6d054cc3c29abc804e661cfc4913e7df2ad8bcb8ef	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x24132cd7c2bf7501161c0b35a89b6bfa830021ce09df8b45d00cd4f43e9e8962685672b4f92f0b8f9b7c2027cc5ea71b7abcc67a87ce013fb165ba8d8cc9146c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0199211b9f70f5f58a36cc95b2cac2c356dd0fc6c74fb56bbab406538385bfb80e5ba58784220c251a9e4cf820a29cadf4e8bcc7261acfc126f22a2db4632db1	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaa467352f476ba49ad8a2fe0e70e1f16ddbed4f560ad7b3ded83cb73d68b8b032af6584bffa2e663bbf3c3fea53c139cd13a5ed16f5b7429c1656ebcf90663c0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x72a3d60908f2fdd3fe3131f5c259e5b27bd61641dc96611430b4928a9f6623b59dfd02a340dadf9ba21a59c9f482152855c604754a26797eda177061f57fdfc9	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x45299d147274da7b6a1870c2de825548b67f79afe6727fd615fccad5aff293c4dc8425b4564e33885e25ffe89eb179030d6376ead8ab12fc32cd24ac47310dcb	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x65e0f4e1562f08ad6feee629227fbc2ef45f1f2e68c0eda53460e531c76a3bf1ca2539a7886ac46ef561e219ad9fd4ecf78176e0b75c1f62a662f92127ad3347	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4b80213469967cc3b191e4cf543a4b2aff9e825e8cd45bf07f8323e7c1b51fdcdbff6c8d043a8f38ecf67a398ad31b96b57875d082d4000d932e8913dd6b1c0c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xebf8799bd4f7e465e7f015523492af38412aa71c802ae48a8d194d9af905fd3388e179ca9bf66118341dce9f86adcec1c7b3789bf0a5fe60a9cd7ee9a92644f3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc11c36acd5942d6c5f12fe14aa558a352e7748a3312384a8e79eb8be7c2a62dc05112bc4f3d7665110f978c8612e5ad3354d21b451c55ea39fb403783ad5557b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6eda6f1964be75db34d5c12a63036ea3ee36196983b255debe1317257f2cce255a8427b82364f36a084b1519a7cd5e988d14ca02436b6f98988046a2ed3ecab0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x30d625ffc5f192cbfc33517439167a6be0cb6ec1b4927c6083fc5e7c270153daa58335e6a7d47a93ee280fffe02720277d2b17e8a1e540adadd7184ad15213b3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc7e208f8e21ce09989c75dcf7766227027166a44eb492374c879e0708ef19858e09975fff1ab187d251c7192f98d53a134bdd92d2b39df88dc2c95f6d0987cc1	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x54d14f192b1a86181326ec1115f711739dc79a0453894cc3099e4eaf6610e84efc8517d8e418711a141a49ca1c06dda59cd24bea496faaa9e5212222d5f76bcd	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdd6c38f115f6fc0b6f346f350f85d4f8bb55e8fa954c41fb3bef36e121d375c90c3badd063def33ede0741c2b3d2bc0733ac9d91413f244eadb8538305f1564f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc6b952b8ca4d5e773aab003f85fc08299ebf2071a5bf4bc02a80f5d17e821856eac2b1acff2b2d0aceb9bf77184f7b60585e620a22ee926ea58f99f77b950d39	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x581d17f4ef7ee82c7da6b27accd1c298373c08aa757420364c22b32489d4d48b0a3c7cd5f655cc156afc4bc7aca9d6338ccc90069de6a5d0776c11e89e3474c6	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf5e8090286a4adee03b2bc4ce4e21ea4963c9b40ae6076cd0cf76b4e452bf5f037247aa1ce456b13f981b40feab30c5ebb221cac6653807e192d13e1561b2810	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x85bce9804085c9a8e41db849828c96ccaa049fed10299f64789ec7d0cb54be903e42980d9a3199ce3f11f691d043a5ead8f62826c93078111310c3440456bb89	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xca40437c3dad20bfc5f95e66a7d6ab5b21394e7a362af45894bc912ae1aec3728b3b872b11e73deba75ecceb12d8a397d3af299e7d8df552f88affd836b5674d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3825eb2720938d7b97c30611cfc27a9e5d7e4bbfce5e0690a81cf3d9128c8fe423d4f1b092eb7cd0fb92ed9d3ed2bf2c81e9c364e61469aa427dbc69c2bd426	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x96fea942f24fff21633500045f68a00c23d0dfb1851480f346e46347f8609d3f17b31d9140009204e412c3d79853e91b9f671ea3c8d9c5b085cc4044ee959924	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x96b77d333c8aa9573b10e62b53b2bd0ced6530e47c4891172baad549ebd9e3fe7e0eb153911ae955aa87ba8353fd0cffa780fd99277786df2fc809d7c5ad52cf	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x719bd44b1b817344928124cce3fd5990f0c129dc046cf69453fd157f91a16b36eb06bbb5ebfca8fef28f4c7e9cad00eccb68f8429dd6cf12fb066c53e9e48c0e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb8df219b580951c005144d2c17bc6a6219b974401fa85d94aa8b3c6dbbb8551577c76b434c75fc522f23f4a510359f4c9339557cb7870d4f46a48fa8ad59a2c3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x58d0bca6799f9c14712f4dc3e9bfe9787f77b77c6a06fd1b2e9f8288b131ee37830af4ae1f2a71b36a5fe104f145dcfa98e2e8becff98238acc4e78970d2532d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x03443a669aeb4db00a9ffd912d8a395a11980681b335d4ab0e81f8d5a12747044b02f5e029ace599dcf3655e2755192c9efa7359341910fbbcbfad09182a4778	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x08cd238a1a189712d99a1881eac9e610b63025e8cc6b9a50c643f79bd986217dba90cfea32da6910cb8fb3dca870f1a035a33e1e55b4f0ad0619acd97ab12a18	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0b263c780c0218171c6654e657aedb36f2a9c1d06a86ee9015810e19a97f631ab902c6043b63c4a71d28ead83c44a98ed7538d4fdfc7765fc592c38e4d6e3256	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdace75e05e870a847892690fa4ad28a8ca4057d00b05eab9957e06f19d7d8a4efca2eab031113813d97b6d5a66b12063793eb8e91972878c4e1fd0d052c55652	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9da7f29726893df1d8a12ab471bdb150edbf9746b88f7fabe1600a7f8e162c7284bbca2da20e9bf2aaca841f7ffcb77f0f4554a0f0817cde497bd6acdad369b7	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x641a25d9c6ab705b0cda2c44a0ba9a586be6ff60b2354a827548301b9132c32e0bb50497e3a459ed895ba638ea03f756022ee6a6fb99451bbf4d4499420a16db	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x385a130608c98f23e4a50109e2107d69a001108f1d3065ed377d700dc658e200d5d2236015853805787bd27be75aba591c27bc9b5072df2a6a9179f3d13a5808	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa12b4e88b2f330402695e60c6bbf2813d84101881ecc12e9ef73ac762aba1429c91a2ed94bc8c6e2cf08309a8b6fbc423c5ebfec28da0f1ad49a7b26ee3b1b2e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8a7e4e8c31edc2667857f106a0487b358d0b8ca962dc82e5a6751d3083c554b6dd04a3db768c9168be23dd50922e1a5f6b2bb7793f02a282e313056371471e6	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x355c6e91d2ea7666d4faa1ab2d2600d4aba6531b93ff0ae8fe5f49620c00d42cd017b9b3821b3f8f1c3bbcc7535d99828aae16636535b9714d52fd6b2f7e13c4	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6d584c538eb4fdc8778f21450f293c4f1100747ca5bb599c4ebf369e267279f7b3f6f33771b3376505d02b280c7a49d681ed910be48a154460ef62cbfc14d5f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b011183b9afc3909647140b1ff57b311e2091d2ca9e15b16b94abf32f101ac6342275617c244ba6c756012ba9ba60415f6661a327950a19b9ce000c35a503b2	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8572040ed93df7ddd60b6c4ca67923a235e63a3fcf84b7a6e32b5ead9ed81a7c92e7ef2859deeb4006f23f5cbe5ed6ac165b4eea30d346d6386e4c390f7fc91	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53aa7ea61a0e63475546ce24322a2da20b39e866f13db22ff8cc111400da928819550935e8a6f3f12c1fa68f70afd4d6a8c6cab28150276dcdbc1f16308701bd	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50dc2307fe5d29efe7bc4291b28d1edf24510a60bba23658782dc3d8d7764a37b8e4b09808845f0b1ab888199944b803a2aeeebab9384cf0877755477779cb2b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c28e001953b3094c31ec81ce20a19e06b3d1a5b6abb2f500acfe1027f43aac09e189ac48e4c2948396bef6f4d12a2a90f643bef5667e4d50bf6f79f4ed21417	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18ba28c519ca1da9e3481ab7cf98e5dbb1b87d87b5d164f7b163f3676731488fa54b7bb462d7f222947c4360d540120e4b3e8136ab592fb4e74345a64199d3ed	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb223d5920591cad0dd0feb10c5dc55b5ba3655e28c9fe1f37dfc5dfc4ab04c80e2a9d2b183795393e955c1aa6f1693674b360ce9d46ad4b854a20f0954305db	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d283f0f62e4925cc0d534716644e0f9a51a09308aae998d7e376c950bc6e0459a2dd92f1138351577b7b5e529a695cb5482f2f35bbd6376c24140a7982e9704	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x47998b02d19be7db1aed42250307f5f909d630d8f75452ae642d032cf9d697d6446e18f9e14b7c8667295dffaf3932059f32d59d8735e02079b2f5aec6d8a4ce	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4841e6d220fa8876351834c721d05c57131dde904595932d2ec49cb4329a69500e43e582ec2d2a003612ae13a2ddbbd4c1632c8d94b78d5c18b97fe7bf144000	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x335ea0bceded6b759ebacbf48bb5b93d380234932935cb01cafe2b9837a79280768ed77cac4af7ba04cc16604deb5bf3c1341881b4a75fd0537d0356e177e38f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2c86fb94a19969ce7b1543082bfaff983baa32b7d309a318419df3f84c4e3ec3a12c450bf05a0669e54ce22f7a7e9d5b602c04bb6b3895fd392cdf259d749ea	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18fc94fa170c5635eda536f3acced06d771b583723b51a1b95f62fe2d9ad55a45417662816379aba41a462c6d45d9bcaaf1242f05cdfcd084b128f80555599cd	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a4f6b02165e797594d0ed0074333c77db5e5a181f6ba65fc41db537212b30690008f23abf6dd5af45d7b1d7f39a3427379347494d5fcc8a77379975f32a0b51	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x928d80d0c92d485c6b6a54ad30ef16e7963c5343391219352e16789589a8ef00df3fe2f181ae6581fc7da16f2ed843864c3924d07080e09fd3bc1bb04c36afa3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76990ccb3aa452a4a8af4be03bd84e0f6bab7a89f191cf140869a312c681e97360d05fd0d84d96aa6ffc41e80e59e6ae91e07dc5dbfe81670476becdddb483b7	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6c24a9719a3e64d205abbfdb86553538fc98cb38e1ee6dede642f6a89cc373f52a11fc5921314a65b0478e4b2fb0a79f93d179b458f046a0a03c7daf3473464	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ebbb924ed685988ae00f07ed367c268acaa674bbf1a2c9c027aa9137f91444dc33d4c98b90e40bf7a5342342118ec80c869e5956055a6ba7574111ad4e44687	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f3ef55f5d234fb3be14a9ff0fad7fe80639561567595faf6612aedbc2b440a528224338ab6c50bc3098bd423ad2f1a547c2fd07e40452555b5989906f9e33b1	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d72fb14851fe61fda136a0337de53a926d46ad76ee408150abe60e603f3286a4eab15125f3157befe081cb8ccbb399dd3e419190ff1d98ae33d05c9de3d4c40	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb9b4a3d4a574b880e21ef32216241d5613d42fbea437b4160cc6434bc0179124e7bf38b18854be66da0ee1c3fa2d0081e3000acb038d1a9bae758ac00815c94	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf7958cff7385031e7802abe9ba3c2b931d721be66fb27a0be935f1e4110d4394c7313950093cc6d738e23948a833027476d8b690f077805392c350c436e68170	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e7a65426f24cac34b6b95de42c5e5b786207c4331a2f4a4558025b76c01cef487e9d9224dff378a2d1e760f7a994ba35677722dcc2dfde75b38130b21ae8acf	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x905e2e8e721cad5c128300144c80be85e3b2ffacf697d3920b9c834466ffbffe458e22ce95b04ed48cfb049769fe1a52a3880183acf70f9b772af8ffcf90d402	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1be97e503e4df71f76baffe8fbee4c623f2b54bd5f7e62a3becc4762c08c7a6421e56a9ab3f2f525c48a18102d11847fcbdc30c5315ea9f95d1bc88807b7116	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x726f628271356541be7d13929b466034bdc67e5457389305ce7d807445c5398c2e009f5184867b689b246b9f539a6aade976cdba6b12eda47e2a8c54f4bc86f4	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbe01339c22de6b0eff23ee5b2e0f90f31d976c9ac4d70b0bc08acd08ae3d87a9aa5ec17ea4dffe98445ec4173b9bdd7a8ddbdac824db41fcdad91c2897c8cff5	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3e1fa208f579273a15eef95d358823faba4c1b00290d5867300f5d2868e4f61e80e4a6ffca36590e2a0610952f0c61eb6958bde664aeb71268c627785e72a48	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15f27171fa4ff808a40d4c2c75235db0e395f45e731001c3255843f1d015a2b4ebd2315f5e6c8568f7efaa8b1dfb567279104a541a107024600ffb4888102cd8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x902ac9f0d3d433e68a2ca8b086023fdef6eba959a889c017cf43a92832ac00ab580bee27c38389d2735f24abbe8220ff0d7d241f3435440cb4f1cdc83b9bec74	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5590af7ea42b509266308a5353c9f4e194b975b613b7ac37845abae6421b32be6b4c80c98fa8fe5668ae9355546213d727483538ad66d52f0dd3ef4b6eb6e756	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x160440942fa8ef3a970bfad149a2cb77cd8006ee548664191b9afdfc4ce75055f861887d513a96706b6ca5614239c86a47c94c78e12665fb919cd2adc046267a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa80355ef89905d36d5dc7c1cc8f24edcfa86b5cf8af1239f1c19ea379450f26e34f2a8a8f714731d82a0ad000265e46528f35a90923a067ee4601ecb24396985	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5ea70148d2180f605b0d30b9607699b6f4f33ac47a6a461e9b0801f968949610b60b2c88bf1d5c6a99e7829b599f6e8bd2d6580a0d22b2d7573ba2c8584eac0b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb8a99287f2f1795f0fdfc98edf6e35622bccdfcfd9fb7746c459275b748e5225a4578a9f9d004f6ff4219f83a51613dc6d5c30bd627db620da64f3569f90ec3b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6e7a9d9e7189616c212d656572b644b9fa28cfa84e2160083fb4c0bc977f9e2f3b0b783ac7f3bc631a3c17ccf769dcbd979e81acad52503b1278ccdb93c86d96	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd4f4fd2b874ae24151b59f06e87dfc4cb4248a0593f8d9b95dcfa71a05d825a58815cc4b2db16d4bc5c9feba40f1596e964174af3195c0f60960cc07b7a5cee0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xead6f6fb4a113907db3de2d53493e337ff789a3ac49b0bce605cc327814084de02d73abefbc2e1e2de22ade6649ed19a29587caab6c663e05f564f6fcae79c7b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe543fd51e50b3054f86d8ded237fa9a336876490e106c32f5c1491ae39336a4794f230cffd864d21d2f2f7cfb60c39abf1b122caf8f18d361c1008de1a78f8af	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7df81f18497dbf12628983508a8274dd6440c53bfd6efde735b4f4878d75114a78fed8a369fff8be5f953f3af18a3f2a388505b2eaa376ba4a033daa38936ee8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e2255f83cebcf5746b1f53ea6d2b03375050c3311cfb7283a3082dc69f5bd1c199272f485535b6ea0d5a0497d3a7c022d21d88b9da12a9cbf9f2beaf7e7c4d9	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa4f65d04bc00cdb25b10261013e5303c540c232dfb37967e03022aea2980c8e703ac3c09fbc513f2f03df594a311ba6ca4ab96976227555aae67bb1a4b76aa94	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd98e124917f942c3ae0507bda8b04f94ebf1d8060344b877531561e7f059a127c6c1edcedf311e7f109588485073a5fd48384676215938493492f56e84d861fe	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a6efe1ff0451037b7c675ce5dc2de361fd661588b2d6e7cf9690da6616e79c4a5029f8949f1b1bbcf757df247745879fa9ad5df15ce69fb42ec8663d464de15	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1390e7fe4d52e7823661c6904275d8ab9ff4dfea444e43d370847293bce7320dc6f14cb110473a8ad46fee3c6a65b1cfb1ee2e25e8677e60296e6ad488f3edc5	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x347048fb465114b55d786852dd164c84df612d916bd478e96f2492de15546f20698b4de2f588e3f0e87229b28012493a76a9b63307c47c9a8ae8bcb641f2afe8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x454ceacccf651475ce5f67ba4afc76ec4b536b0ddbc074b614435adef6c7cecaa7a142560ac0ab1b61efe0479e34025ea720a75f0ed229d8b1ad7026fc65f394	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbab8a14f55241d70f535f0e72b6694857812018bcf8451a9d8cb3d60fbf332aeea1884b7e3575d7c77377b0233e19b9419d0b7f227b551479ca4d002a926d036	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xff41c14ba1b6572dbd5d9e8146a7c747f27fd82c1ff51e2d49c077aaedbe7c5cf72ee15ef2b43f146f0dc745477953f2fd3bb9cb7d779cf9e543efb4eb721821	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd83eb32e1c8213ed39f350251f2c83a62932e40f132a3302fa4ce60938f132f605b2d3d41eb33a7318a40d4050944c7cf50e05ca27d97a772fd25d2a52599ee0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6dcc8bc42191392383ff3a014b1d170c8323b26a59c16e7c9a508e832aa704d92b8b6ef3d58f84e6d440337f3f29363fe67cf243bb136e438bfff08f346f2859	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x34f35d682dbf7f6b0914dac160bdee7db26890e37619d1d15de853846e79960312fd4adca7f6361a0403f662a563880ee63e5edcfd71aed11750995ae794152c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2dce16e89eed29a0e0657ab751fa2778b12050a0c7a54b0995a83ed16aa92fc3798b17f11241691b5653d74710bff6073f7c169028f7ed50d80b12588e9bbc98	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8266982cf7804070b44a78b53bf7f16f7d7522beb18f7557b5835014d11a55750a6fb398272ff5fa46a46566510eab394bdbec2c65810ed4cbc145e51009ad03	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x981aa4a79e50db4925c96cb1910bacc7db89c17f0d4e32e5a7da759f466392463078925f2354625f0d9a88a680fb687aad0edb7a17fe8edce40f46f8988afb03	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2a4e38543fa48b565c22e48c3eed131b938b5b0c8c3747210b6962178c0310a04aceef36c50b3b7da0502863c35a662ee7292cb63a9dd03af9041dcf56a49a43	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a10bfbf04e1c6cf6b6566540ba86bc6faf0afecb4103395914fc540c24920ecdd6f03b79762808e6b3e816b2f2f1841dfbe80afcb5a42a56c6aa7d5d90ed4e0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x17f5da2ba3cd8782bf4ae8d5681a3b6240bcc4c90f9d461bbf4898976d839117c6c2f703cde8be13c78dd017a758868beb908c098c563bd03824c3115b3bd576	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x677d96b824b244e6a62da32053f67cdcae36911338b5864eaa8d5a986ca2147f8e4e3fb53b6357f283086509f1016d9d1f390af40de5a186e6e73b1305bc9f96	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x21ca925499d96506d830120ff6987e1793211ce5d37709308882ec1c81b6493deb499cb842ede6132e3f19b9f7942349a2acac8f5f73c580732052646d0a2fd3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcabe8c00d56fbd837d1600f8d7f1683da3c3c695c37d9c6f132629b78cbf34a845383e929b71d95103868ef8f197cc5efd3b9f917e4055067f8bb13307007027	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1f29731d3b4d166e9318be634e33042ecb26c9c5266d7eea13c8b6d299c31c78e28138dbbffe51c4758b8408bd89898a49a7f840f681690d050bae86ef068368	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x791ae36b3822806b77abf82313e83137aefdee4f0db863a2d5ae787c8c2cbf5d3022ff63bb7cb41ec877143addb478915906823d80c934b0fe02217dcb2bb0ed	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x45f0f150e169f28c8fdcf29ff8e6542fcf85ebf3365e08598838aff9fa65cb5bfa77d2071f7b8938ff8a392db222710839e1edb538f42d81c29161904e2cb52e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2e53fa61b82f7811adec87a0f2775d97a914f3e2960235a29fc6d929e60951c5239edbce7fa1a0c79447779b4f95debcda34023daf4c8803e0b0baa6edec719f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6d5df1cd8ed2eaad50a8cd51540e7049556dc18b85c465b6ce3a06d93da1d3269a9edd95de759c10764c4e6b7a2d2b5172b9c957691b24f317c153ab0d42b135	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x43742e1863d68cf1122ced2a2da18bb3f89f36c545f358fef7289ef8c6fb170fd1b1eca409540012b6ce3395a913b523ab4b21a68b1535d53435c162f6890dcb	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3706f908f1090b16fb7d5d9167b41cb3ececb54b7e357f8b1dce01b8eb6a6f8ee7b5e5d676d494df041bf80747dbd29731a176fe820560c0d6832b3bde1d931c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x41bad6a5cf0db351db6c8020fb7547f1c4da592efed4f0737bb44149168a746857b56d8a05beac01d15f88454ce1af372e5290543b6a88ac1270e8195639d47a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4794597706f96a2420a03e24f1a1dff9e40ce3833766abb51515fb00157e8311e61fecb311fb559ebeb87846f320b9b74bd66a9e885570eb2db7229d7b6b98eb	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd9d935398fedba2feb9bcd9144f7be1a319f515fb210607663319d2344fd00794d6a7a8e5507c56c28e422e2ac9d0c786632dd9de3e036f9f64ba1ef111bd173	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3d617011c3a7b6d745c0a44258a1e0ab25884984116a5b80e5b049f9204d9ab85bae68d1cd1eb9e497bd6c16807a9d3fa39070e7aa6aa6194620df373a69d19a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16de1741be369fc863950014ce9eabfb8c5e0de4f6a79a613d8f91f1673bd34132420f1b92382fd6b1b90fe8ec464e248097b0c66bb8c243a884c19ac812c8c8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x339d0c14b23c34e9c3c32996d5ac9ab6bd6d59661afb1a44cea921f44cea7f62967a4154dedc568821ab39d08634ea214cf2518b484adbe17901b4b4a2ff7e07	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf87c221b5625d0f1ff033c975ac710f0d0c72d385bd351adb170c5e5ba1db74cca36d73b068ac1ab8556c4c6b20f7ffa13bb373d16da87e5c44bab4635906df0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd72a15c2557fd10196dd24f23e824f731e020a772fb255bd16d45743ff5f4839ea060cbefae13bfbd8057f8254807c6f89fde94fa64c94a79a9dbd623fa526af	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa2cf3b26f7b04718dd6b67ed404fb059c8a24765d86ce4b4b2ab4228934abe899b29ef720ef1ff475c543c108799acf81ba30f2a59e1184a9ddb08772ae2d908	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae1d65071831c74daad6387fc8b02e83edf8d267e0c1cb19d622e17f7b026c4f47605edc7a2391b6699911f7ec1ff79e62b084b16360510e456765e9cf7e413f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1cbd8574613b5ec6e4bfbe71449e5265747197260a41faff31e967551d227711839e65e01c48f201142d2a82eaf021859f70b547a7a9847aa3b579ee9be0801a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd6aeef9a3971b870bce1bc3eed021aa5e55489eb33f134e09881b5796209826090e31e3d323a70c6d9f48c6e7855f1fc39ece82b6e3ce81fe4eaafff39025ad7	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe810cbcaa11add392db07e09f9be00e14cb72ab97dd8585a74b989f437a322cd6ebba8ec47d928bf8243e7f6165870e51900029d8c54602553912acb13d4a0bd	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9284359dc3c889380cd55a2e861f0ce20af85debb6c5983b2b0c5ddf88e558af19382fc9b2bb13178a0a4c78ec570ae1b80e2f042848101d6d7c216d46ed2585	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85c025722290e1fb9fdc19179e22b0862f53924b0636ed4eb1d18485ea75ad5179d628550dca368bcac9ec7502ee7cba1c33bf2d24db81db1d2c249028c63a77	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x02823395b52e4dfcac48f63e4eb65f580a6a48d1be306f2a9ad64741ad153dfd9c6c91c7cf595f4b7c23c5a3a9fa248db445c46f0dac0a0dfe9b6f37686eb0ca	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5854ce408f16e9d28197230a887688d1dac5e451d57e6c63ff068790941931c4857bff5b22caf74d1c4ab6a76ffe5de3bb8dd2e7ecf74f5c9c1bc937bad1e5e4	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaa21305ee5c7ab312f987000526a136a32d23eebb76b729da7ec190c760c8d97d4ddb3e843dfbed0d1012a15c339b83613bcb247900d65f25c70cfb73f9938a1	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x998012fa0bea3e325243d3701fd3d2c34823ee18208f56c9aaa76a371c9d8f434aa3a8332eda30585044c5775b0b1ec2a1239bfbc424f6f88bcdd173c5bd190f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x501c0915de4c6af96401c675eee4ab4241a4536366eca7ec210de8c4dc5bba6d569dbed286ae01a824e3e7a29efec1a85ea036a948438c0061d93ac800c6377b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf24ba0053ccf707089c2e8202d61404742658202048866e94dfa291ea174ca4de735cd64ca7250b58da5cc08f581275ac95ee74bd94fda9f3ee3b2751deac928	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf5a8ab03fa9a45918d630c3061ed1afb29bebfc8af14dc9b5c870d48be5b201ddfc8de069036d5a15b893098f9a1735a3268f38b19350149ec603c4c2fb36a66	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x525bc2e892eaab30d63d186b4fb3171176fcb2a9b9074f2b431f253f1b6bb131ce56d40ed994b736686543118757c2d5c70ab7f661dd160cc9e83e333e73b912	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb825fd04509ad584bd348662c71e0261325ecdbb6a53923f76143af79a2e3ac03777c3123dbdad2613777b4045090f1036449a5cf67783826fd22c5e42fe58a9	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd0265befba3dddba12b8e6e7c5db1a855b291d5466f27f102c73c89b911f2a786728a18c25c76e1e1423037f29524f084c8389b0b3a3857b5ec5f2e78ccfd302	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x821903efb945a68897662f4ecf1bdd13411b300642d7528f3ffc98629ad8a5808dc18728184b2b96ca4952679597a58f9a551386ac19feebed8317733bc17faa	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc281e7659aa00bce42affe1c658326c8d348caa5f1781f16d2786aea07bef61dc0ab692f233873dd698e1614d6fafd64080130600831f30f7fb8c8bf103024c8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x007a723989d0fbe8ae2e8213897d795c53b898d820b4184667f2f75f2758c65377d5b64e3f041caffc8001e52a347dc03a8d74a3a5fc8958fac4d3315b979a9d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x97566eb49e7b3f15a99ea2204ea4f864d042011432b12131061bdf533a99eb7f0d1a411dd845e752b947084aad77c128184c75b6661f076c792716ae01683aa2	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd103013312035f16c7b6b93193595a54b4e12370f1901262e645b8c54b56c9b8eb12fc39b59fbee85701a736ebbc91aaaec0f48530f2efaa838deec2fa28222a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xce5e016582e10ccde7cdb88557a0c88488bf7bf80d2a31bd8364a481004aea715085835185131831ee77a55e71193c473320110cc02ab8bf10a659a9eec06b51	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7c759ac2d41550e6ed278b8bbf39087fc1ddfa4c0c670c587827130482168fa295f8acf79a207b542175f0946243cab7c4fb0e7c9b8e0b42846364b4202fdfc5	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4ba7fc509b90448664ae42a58f5950fe10d177f7bb2abcd478fdf9a43c216aec6426c46f56a48a6e7a87babffec3682e8ed1d8c4d024b65d9764539c81681c47	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3a5bfef3ea5f703ad2520df31e5780b102461d501f538826b19188dceec9cb483e295fd441fb943f8bb1ffba13160329a1f1f7b3b387b8d5a48bdbc63b3b1cb3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6b8d3f2a095cb81152a304058aec02cd7544a68be7d54f11fa68f7dcadfe39fa2466e86681be05732aea8e74ee1fb738508c0431ca348d909f3ad9d9e0293a76	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdebce24c029c682a89597f811ffd82fbb93572e92de0822205f4656796b4ca1e6b56dc02c4ab7a1e0b4a5c196517090d038e07b2b237eda1d68bfbbd417922a3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x297789b16a1944ec085b4da22e859049fdd86cf27238d0da6f6c477d2001f95ff9ee0888efbb3eff952c564f2dcd7bce0bcaf95906dd98af8aa79d6a3a27ff6c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfae02ac97aa02802091e12956a13dd1003c24f58a1ab14735827cc848cafd15eabd2a992f6c1afc3540fc89ff5f77d6fd157f0e6a7bc0c9219e641109ad8bc2b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdd0bd3775caa5b542a58a4a8a7f1e191b18ed03ec2168190c3064e253599882591250186e3eb82e98d87d03f547f07c249f615d9c723d178dadc00f1c70e62b0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcbc7d87704da3625203d37f8985c8389dcbd90f70e22587678440582efdfc69f187e3f8c998ce9ce48d57f52b65b9249739bbd900c42374a64011654f530f5d1	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x52775349a5c7f061b9237d559e8a71ba9b89e1f6547f40fd68ce647db6b5837acce7c38a9d3317d488db922edf39787ac1fa4aa52636e989b4960784792b8a0f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf348e1df51dedf9092187b8442ebc21945fc1695e17fe7c664df511972aeb0a8d1cedcdfdabad7577bb15b24d12600cc7ea827244f03c14536eb4f33fec3e77	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x86ce5a257e4f1fb87bc5b0105074f24431a8dd2ec773babf0af0bf3e1ea1c3bb9422aa4b07697cca1dff0e5b01bda06621a547e61b5d0c92d90a1945ae484f52	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8e886d869990526e343f8c2a16764b17cadd621763e5bffee710115b023950b3b420a8c3a5a645fc8417777c0073db54d2e5dcb1b08ad1b1b42394cede6f6bbc	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe3022d74c93236f33c785bf9af4cc727fa42be1356bcc461765c9621232da7358fea0dd7797399af80fb480df63cdc5641c30b1bd8ab6c4a276c8805a495dd4d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x13d62e7c2206b551e6ac37d513b309683d1dad0aab669d03838e7ed7853c899e2f037e160ddaace2438293f20b6da2dae178724c0ef351d950beece7b8818580	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x84691d44ad84bdf15abc17bb7e2ed145b1ccd37893653a2c51f08e8e6a980d721cc7be07eeb4c62be42268ffcf339c1ec6f119d46c344aeda9dcd52b09715e11	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x267ca04d09440240dfdeee7ec6ee3009346bcb1ca2d86566923310d0a716ff6f043eccf677735bade1293c5197b7e18cc63168ce03bf385e179e8bf19b339ab8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5ae067c5b84ffe93e366a4add6d3876798b41dd679dcf61f2becb7036b8352de111a2164eaf6151bb355efe30bf8fa360e7f1b983488adec3c06672d0ef13c09	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc27c3767aea60aee85fb6252adda4af7c422a79ea3992d395d3ddadb14cbb70ef59230abc0e58fa41589df489f83e558458d22668fd75f1d35e4bf98465f9916	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb95ec106dd826e9334a6872b9831e9ca6d2d672c39690e7caecdba013f5fe0bb295926643b26481f6af73304528a9aeab2e9bd65b9fb23492abf62ebfbc5d297	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc3bdd5356aaa85d8eb3a90240eee102fb76c5b6af81f38ffafa9a2a9807fe2894bcd9dca0560419786b3245ad4d5758846d8199e80adebd77197a79ac1348046	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x266e271b1fb42209f13766067730009c62f51231da014ae9cdd3143fb5b36cf20e1b7a2b76496d252ea68bb38622da49e3d7182edd360f4dd2cf9583ec631b13	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcbbad4dc02d4cd519965aa4b7054978c544109692b2e111506908cf1999fc86c97fae25b011e76611b9c90718411e2de180b221c1937d52a6fe89f15f060da70	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd18a9872214084f692e9e72d049d3fb00c9ea4ff5bfd0efc13d9f20db061a643b93735da9c3aa0aa585900d354737025767fc5bcee94e45d69acd098ecdb81a2	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7c8d09bf17d7bfc056c111adc8021950a0caf92f3db90354f47eac34454ed2a6cfc1ab7ba55a994d2319f93c8264ae45269da8b801e8638f4d376bb7b6ef8997	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57971cb25fa3351c0c390140d146b07d02960e0e6b848162da12627433db6579d56a0aae712c848d7f9af6b866962c106da8b696501d632cd4439c3e3532ce24	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xabb7178037685235262109bdf864976786468618bae0bb7f6686d18836a862d80ed5f669a07290bf78f67bfd40285c2eeb6cd2849fcb9d1f5a2dd3b5fb3ed30a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe77188f6ad4fb2c018ca1c6f55d6005e40dbdaae6530beb8bc28ae47bef61df1619ded2f5b4f79a65766163cead34e5b1b0674e6bdcf6e35f3fca6ae87df9999	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6bc31a9070e85f0e6ee6b198d9731255dd0c1a54595cbb87ae4803017ab6dd6c2aa6843376ee85cf37a9c43ba9d733d1e3427430e53f651abb305cf6156d10f0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x827881ae88845d19deb37f9840cb0688ac4f7140a4e3d10305fceeb53ff89f274e2968b9a8a97ba25a89b8b64fb51c8b663f134098c98955b07132e356de3f3d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x12bd4366f842fbadb6d819b2dd4673bf6fad076bc38ffd9c3e9b2657a39cd27ca64193de12f84793ed4ea22a66164d63639c5d5a8c28c7f9b90fe69a1c4d124c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8fc4c6a30f2e671b1c5f443ebb72e073f696d127a586190f2a83dd4e94ba89dabdf7e389b6e35a06d4916a0d557be3b0684ddc2f64fa66c2cee75c243390999	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc4d4ce3fb693d752a46e6b918f5446e04b3f8d51e91a38ca72e2b7cad15a18fba3022f076bede4cf6407d5a601dd498179912a28c8198024cb327fc6fa381a5	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x558cc61ff46eb7b146e519bed79dbc9ff181a421e20052c3007bb6505a5ac354648af3f21bf54e6b7a860d50cc27cbcd0b076fd57f0b2d9b8cad62e81d6d88ae	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3687b9f79740a56365e02cb627c0bcbd01f7a17ec56347a4cf00d6e1fc37f398d9d15b426981cbab6e2e8e52d485a0889c743848e0eb98c8920d0c36f97b9fe8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x087f9845f8895145b21addbc51aed7c6a38b2ccd9613ab2cb545c07282e38959dfcfcb51be65fc33619eb4fbf29ee6380cdf1a01a1923074ca8e605a7506fc82	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c00bf6075ff97f61c48ec4dbe4e06083d5470de63c79d480f34f285b9aa182eac42d0737a7d8e090299a29f35c8d9ba5581a2cbfc0bb0b2726f326583359167	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x49d85b405c110abb55f543e7383a23ff3c2e251fb4e6866c2c223229f9bfdb9d5069c9ecbd14f5ef259f557590f3f32f59675655a06cd076b85f68b354c5128d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3231921425278ecf3f80aefcd15dbf5113fd58b43c9d2a06bbffba0ec7dc40e415d6742beabf650b99c8da8166853b2757efa323c39ed9611bc2bdf3c70cefaf	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x82eef524bc915fad22aff57cf80c582156ef43eb2d51a699c7cff28e22f925124ba2612c5b614944006c0420d61ef51d59efe85587abc51b0020d98d4f6cf96e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc000051090e76c4e57c8649c5226b207197c0a51ed86533c2569271fed08f45880d1e09a1138bc662a14204688ad81bf36596cb74a59a524b4ce164d43c0e28d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2bec24dcaf856a58477a4dd9536e25ad288206cb8e14015f5a3ae4c06a8d5ea49ce8b49f1c451507ff8be02aec5c1f1631545c2b9d902100f5c8b0041cd21a1d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e89c92c0f6d55578877be963ad18e7e91d4954f7c16f98f44af8d21cdc0ba9d2969ecab6d1addafe4074d0f6b2ad1d0585c5797fb8c88ec7317802bceb73c5e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ae4e26b0d61a91ef714e5de674639bf722fe97f0b35f6c5c474f2be1675a3f93e3c1202dd67fbe83dda1550e1cf51fe5b3e9ea2272cb8aeb9ff713bf1099540	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f7757d3308ba79330d3c9ce1979d24dbf77bfde9ba9f54cbb9d2d4f461744ec9effa181462e9c72fd91158532f5d6bd7591b7c98bdf230afd130e78a13c81fe	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xad02b3fc69364a5b0fb6aecf8cc7b561da8c9283752ebe7021c0cf6c8938fd0f1b926843ccfbf5ea109a1ccd168e461202eef584cdbf38efd591dd1ec3395fea	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6dc7f559ad308c724bff49c46639d51cff3401a35d0db6e24a1521eba2883b23f46bd662d8822def999ba501d759f289c673354ea91a9443e3d57b0ba48d81a1	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bd8ba5c390c529abb31f5f2d2b8211944f34a0c3cef9c4eaacf34bc281203e713563bd4804915479b8845706a230cea75bf1d0bb22c390f9f860eb55a478e32	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x94bef8859245d4d62b85cdd23ba72f42035db7ccd5eda2cf0c2a5f5e39cda65c78cad04df2bece63472c0ec0f66df75763f58d8ad98b12359d5add4c4576a33e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x33b92a4a6e03c74dd728d361893e2e07cac9a2d68b075e5b2cfece8f887e1b14a9ffdec2021854d723e5c8b8ed4fa53d366886383dbd03c07ace2537acad1347	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c99289c718b4c6e18608f58902f609ccda5224c563b360a0654b4b627acecc75a16c680535451e940588ff55148f93fed117596586024581d0f34627f302570	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x782bcedb4c7c8031fab50ebf79cc2f3ba45bc5dcc685816b940c888d142908b7c285b2fadd5d1abe1266b8303234e82a9cdc4f3cc9c2784a98468f93ec764c1b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d1fdc8866dabce9e11db076b7c27fd3f8f45acf69b700cdc602ae0db915bb54a0032c59adabb5681edf8b692f3f8694dcaecd7c8e38e342a319adebd9800b22	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x124287cb2dc855abb94996ed95f1962b6c6ee27d190b8812d4f9163a807d4ea53f0fa329293dba99f8d8779175cfa7ae2e4f982bf37f030bf6596d75b8034ad5	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0d617913e81146d2206198b9910d52ada335ed1de82eee7bdce2543cf45494a0d5d16ab540640580ba2e4ae072059ea5da445de2780035f48c71ff71a69ca2b	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xac916b69f704432dad698e136c022b217cb4c01d510ce9d6bf6e1007b2d311fbbb686c8a899b54b536bf67bfcbbbedfe6703291a5ee3bfd43d98a3422262b853	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcf00dff269abeca09c2deb2e7c670926eacd4fcf23c4b087044edadf7337077936b8fd40bcdcb2136abe459c79d87cb805f93da3ce8003b2bd0bb00c91d9709c	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeca9b71e64b6b04f1a93e2e4f822f067019bbbe86df30fc42348960939cb109fd89cf006876d778799c04d70e84d6209dc7f23ef0ab855b8ec85fe7c0b545317	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1567401767000000	1568006567000000	1630473767000000	1662009767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xae454caad46f61439a3de1b8401c249fb6481a3c2220657984d263877aa73d25f94e6c6b2599de599bca98250cac629b8e653c0b8107aca2587a55984eac20f5	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd88af4071eef2f57ef41733d82b47b9e6e1842f3a83c1e9113f6190875243027903b3d8a3dd65caaf2f40da82cba1e7e925c9e5d457078e76e4f2a982c01cc83	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1568610767000000	1569215567000000	1631682767000000	1663218767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfc0dab248c3765858040d86959247acd41e8fd63de494a52bf18929e9008768f39cc901aee1c74ba8bc51dfdc2883d6ca9af2064b0cf908edd2c0c656097e2bc	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18a914f9f1e9a639aad95c40b36a704ca80233ac15d4155bf70b5c98a5373c55f205edc09d32887e768225b1570007bd76a6238033780bd7984f9ca592f5e646	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1569819767000000	1570424567000000	1632891767000000	1664427767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdbd5fab08e5d9bde993dbe870c31c574b6ba91afbbbaf81108f0a2febbc659092deb999f72183cdcb802c6314356796a5bbd54351ee352bd740cdd108c92f911	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1570424267000000	1571029067000000	1633496267000000	1665032267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x27e5e785a6466eb72bd0e51dc19b5325ce58b6d40023e5e5c364801b45b65cb12b1efff5cfad61667adbccdab4450b90a84e9f4ea8eb910b3d5a04167c2e6bb2	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571028767000000	1571633567000000	1634100767000000	1665636767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x851e46cd77784ce3d6184713badda12bea1cf59c83e8d63f6b3985b8112e3ff85a7cd35114d06c52907a323b0c67f215caf483ebb2f4978a3ae78ec44cb14f90	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1571633267000000	1572238067000000	1634705267000000	1666241267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf1aff332245a591c3ebfb5042590434ffaf1eb2d9d068bb5a8eaae4fbda605f3b532a5ca0704d16501105d689b17c5c5aa5aff9e3c0310bbe73753550df7e16a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572237767000000	1572842567000000	1635309767000000	1666845767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x109d0f630e26c705aff663c8dd371ae11f4e331ef9a14ced711447ba58ad80e47d6fd2cdec5af6cb7c913ab469220ef39c0c4949926ae35e98df3af22771b2c4	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1572842267000000	1573447067000000	1635914267000000	1667450267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2361e5ece290a95232f7b6ea595ea59ac9fed1fd259c961b152aaf3e8404c10e356c100f0d3a269732cf0e8d425c0c81bf9fbab05e1ee6a37a0313e335f245c5	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1573446767000000	1574051567000000	1636518767000000	1668054767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8412372e23185c626d71b83a7b39f8a677e5316f3ab1c45305bd43cd967f61e4c2db358b7150b491cfdb1f7fbffb357e435919d7730ed673cdbce6236a80bf83	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574051267000000	1574656067000000	1637123267000000	1668659267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x75ddc9e876a0adc95be165232be074c87780e54f08d6816d394144902c4d7192d55e3c47d40dbd097d75ec5add282248d52fdd7985507f18efe9e0ec3ddd08ea	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1574655767000000	1575260567000000	1637727767000000	1669263767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3e30301d14f0e89e16d12d895becc74680c55117d35e50115a33a73b30207a023deb2fd41ed814a5b014a070ee8b7dc5cccc325adbaeeb720ba7514889dcb776	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575260267000000	1575865067000000	1638332267000000	1669868267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5de916660f14eb0079d6928fb374a2208a51a0e9e7f567d7dd5fdd30aece9fa29be5125f29c87f218d74e28cc62216afa92f977861591a248ae28a37f30e223d	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1575864767000000	1576469567000000	1638936767000000	1670472767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc2501b5177cc065eb10e56000fd4ca34cfea36f7855789988b1b90d58096039081b100411ec5a005a28609d63a2696d35525613562e55fdd4845f9b829c39fdb	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1576469267000000	1577074067000000	1639541267000000	1671077267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd0307ff857c093b474b53762a470303df046c9043e9445f5ea175bba9932459ab0000634b2e72a738df1e6e4c46451fd40ee2c8e0fb6c9584c343428119f7c65	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577073767000000	1577678567000000	1640145767000000	1671681767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcae63db2c8b91c619cd7813774ab52ea6de3dc57c7230d7765a36c63b87b0f07599bcfca0f4e45e6bd0a383d10ca194442ed83f442133cc9cc2fb7898e4effcd	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1577678267000000	1578283067000000	1640750267000000	1672286267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1b45d7b9ffed417f2872585ec7947d57bf5a434e62016c31dee7b103e3598139fe4688176fbd440291e6fe57f0d514b165b26a6828fea8e1df2393bc3d6cd05e	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578282767000000	1578887567000000	1641354767000000	1672890767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x32467454533e849c681c95ff90626fa20854a217ac9ee222936edfac5e72780d269127181cd39df43366c4c6897524534194a9e8c19da3df46f3958921452b16	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1578887267000000	1579492067000000	1641959267000000	1673495267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xefa60244ef62cf5beae375401ab7b3e8b091f603e304782be1215fa69995689b603924415c5c40cfd6c7cb3479c8e9ba56c26052373c99e2e88d5b25589c4a12	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1579491767000000	1580096567000000	1642563767000000	1674099767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x088915c55f43b16b34a46c263cba7e5a50678e62bd17c02305bf4ea7f5281cc4ac920be518d137e3bdf8135a09ebe5b1e5070ef9c9f24f3552093b1c15fd4263	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580096267000000	1580701067000000	1643168267000000	1674704267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9ea2e78fd890c08d1f07ec70668719e3bec5766c0ef2193f5615e42b527cc181744698a711fc0a24d5c83c0e17602810fa0ac015496ffdc61626204b8cc91e64	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1580700767000000	1581305567000000	1643772767000000	1675308767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x035f8395f2ad98083ec6d1910d219cf1b90b540cbe68cc876206bcc07b17d46a363fd390e605402ef70c48c6498cf93603e4f475b22e81e2fd2b4b4e6bd027e7	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581305267000000	1581910067000000	1644377267000000	1675913267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc289eac518667dd80e8d709e0d8f6e26d7ba4135a0000dd30b2881a51453cf9630840e1ecdeba477335f989c92714876a29cb54185286bb11e2c95aa54f255a2	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1581909767000000	1582514567000000	1644981767000000	1676517767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xce2afd5a4759333d4376ecb4336f29783858476629b00a4712ac158e9c6ead243e42c73f0d9bb55d6861bd4634c0e5d06370bbc15002cbcbf01ab13c5742b13f	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1582514267000000	1583119067000000	1645586267000000	1677122267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb2a46e009cb1dcdac4386dabc6f242abb9633e6542ebde6670bdaf9c0a99493debea73601cd952c2006d404e9b3118ca337e3468d9452fd31ba0e61f2d4daed3	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583118767000000	1583723567000000	1646190767000000	1677726767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb21d645c6801a599fb5c09b5b31a3159dfaa2d19ec3082ff7cf85a7fee588e369aea6fc523ca0437ac3363f266d45ed5e324be9721be18b5a04fea6331ce6856	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1583723267000000	1584328067000000	1646795267000000	1678331267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3cb31f7c1b1664421ac5623856977738c6f0affd9b279d60182a1f78918d5150687b0a5ae9ece6b36740344563dadbf5dec1aa177771b4f8f4d66d1cd0fdfc88	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584327767000000	1584932567000000	1647399767000000	1678935767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x38d3d624ac9584dbeeabad2ce89777e9073c3dbf5bdf3d0c716e5390fc2d66aeaf372aeea27f9a2d935bdaa0f62f20d8ce6b2bb5e7c6e064f4fc7e3bf77934f8	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1584932267000000	1585537067000000	1648004267000000	1679540267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbd91727f7641e0e38a5e0075b7c81bb1e37fe15f576ebd7dd29a87aaaecf91c3d5718cbf72c517a7d0e4523942adcd909df9d14bbeb5608c019b5b217e744676	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1585536767000000	1586141567000000	1648608767000000	1680144767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x68f6c025e098ad5a957181fabd64c59a64152287403ac1d4ddeca9b5bc96ee013646e9f766202c676dc69d4d36f8538b9283f23f4fcc7a34b7a964123d4d8bd0	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586141267000000	1586746067000000	1649213267000000	1680749267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5bedf2cc0b23bbfeceecb9118bfc9d0ced69e071fde796be172d1126a31555afcd805e0d352ed6d71c6fcb9fc946a2a0f2bc9233d8b156422e79946ec9e9f90a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	1586745767000000	1587350567000000	1649817767000000	1681353767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
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
\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	http://localhost:8081/
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
1	pbkdf2_sha256$36000$TaWtfjIBBFNU$wUM2e4m/263ksyHIjdCCJYn0p/9CUSdX3v3R+V4+l4Y=	\N	f	Bank				f	t	2019-09-02 07:23:11.094548+02
2	pbkdf2_sha256$36000$meWq4PnLmlAi$KWf5rDD4AhDagfZcjsT/d7TvFra1ZsX1nNPtSmJk6Jc=	\N	f	Exchange				f	t	2019-09-02 07:23:11.184224+02
3	pbkdf2_sha256$36000$RG9w39CTWmPQ$6C635zJjaiKsCg3emIAYBugKlPUt0GzIbl9p2yTlZSc=	\N	f	Tor				f	t	2019-09-02 07:23:11.251031+02
4	pbkdf2_sha256$36000$2edVbwthR0lK$rp8E6LApwIiId9+9sofJQxgX4cVH9u/hCQ9pzFwPmww=	\N	f	GNUnet				f	t	2019-09-02 07:23:11.317029+02
5	pbkdf2_sha256$36000$68DVUO7hCtiG$5AJIXxNbPHEuSMmxc7Hm3KeV8T9qaZguq31egsrY6v4=	\N	f	Taler				f	t	2019-09-02 07:23:11.383706+02
6	pbkdf2_sha256$36000$SsgeomdUfIEL$KNYQrVrezGwiEA2JW7xab3E8CO7Nd4gKrDXCISwGaeg=	\N	f	FSF				f	t	2019-09-02 07:23:11.450148+02
7	pbkdf2_sha256$36000$6u2kzOMy1glN$A/rmhD1RwjhBA+rGhGpc9R3kQafaH2O8q1RU2yvXu/o=	\N	f	Tutorial				f	t	2019-09-02 07:23:11.517143+02
8	pbkdf2_sha256$36000$UAFi1RHpDqh3$xWYOo9Pe1bAqaBZHZf1JpAQT6345wrjcuoRJC0k4kX4=	\N	f	Survey				f	t	2019-09-02 07:23:11.584315+02
9	pbkdf2_sha256$36000$x5DsKDXwGToc$lfe90/TcnsI5zaDYuRPZEARilXC2NJMqCB+pq5IE3+M=	\N	f	testuser-gZishKyd				f	t	2019-09-02 07:23:19.296254+02
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
\\xa2ec7f7a6fc36923a21359b15e84dfa482c7992756fc6b91a611e31b871d982eed261c4e21c76a6004b922ff881df1ed83e69481a4220d37a3a8608a0603e7de	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304630443936364145424637383842434136423931334335413938373842313735304434333336324434394343303641313046324143373838314132383034443942313331333445394531413433373237464541353942343435394641454245393337433132414442453038393643334635323538333833424435453636353034303032373444323035413441453435454438394333413332433332354341424636353544463639303931413131303730383331313741323446344441353430344336393533323732363235334237463444414245313242423945383646393033424138383031363031443745413641373842364543344542374433314239393723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x7b6770a4b8484047f64bcd9f30ce91afdfad4714d929e76c6cc4baf292d9a6c3f98fbd577e1dc7aa4ab4bab7c548cf71da84bdf0b5b6f8f5f746517c930a0c04	1568610767000000	1569215567000000	1631682767000000	1663218767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x58f1754099672eb64f263753ceddadc6c3ea9e01834fd0a51b065d96ffc1cf8806367c3bd4a0ee1aae221b05fff7d306cedd98abbc314222d4f0919565f523b3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433324538323832453032434642343036303737413037433242324146463843414235393346343134393434324342363845333234333034363131443532453137333946333138313937463335434630434539323230374234323944454232364230323843353031424646313035414341443846383434424241454246414537453544393343434635454434423034313538373830354244313632414638464631393031454537333735393633443839394137383241383042413033393144353544463639434131343843364533343038413732433642414438413034433343383137323639383238414144394431363242354133343641323334313946384423290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x77b2580cba4ca825b37b2f0cffb9b79da1779c946c5ef78df39e97c7589b81214afc660c3da2106c2338cb7d384c6a53f0bfab0fe4eb6388d0caaa23d133ea06	1569215267000000	1569820067000000	1632287267000000	1663823267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8a5aac29a01f36746f2baa61c818aace568f453ccdd4cf13442b4e94b9a1f6e7f151a22e0ac4b112517c553981a39e114551ceb2e4408e75262b31fff2f1b7f0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304538374234394342393844424633433037423734454534303533354446453845383839304135434446423632413233303844333630353043313233463032333031313238383432333536424532393345394237303744433742434637414636303231453145353338343543443942413543353446363634383545413046443433343743444244463635444145364134393739453131413631343932443433443344363538343746373146303633423631364334423843423430334530383033464246463443323537423033413334323146333142463534424346374131344144343242333633443638384334454542343235304437393939463530444338374223290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x96b40f75c0ac0ec34da7882791c8df7195656fd61998f7dc0521fd7b8d2451ab96daddde22b798ea2c0a1cc5bc2c8d04e193481af75286180b7046aad4782e07	1567401767000000	1568006567000000	1630473767000000	1662009767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7a4eed6bf57300c29569cc6c9e7b483a3bbb53357be210e0e6c7fd7be47ab5623d12b8c93e413dc1b1674e6d054cc3c29abc804e661cfc4913e7df2ad8bcb8ef	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242304232333243393246424546393143443231304232323737373431413943314539373530413038343536383038423936343446333439463134413036423834314131393345303643424139334431423935334139394438303441333330313841383638424646303037453843394244373135463945414630394333463346373634433837353533373939373644303244463134423331393946373744423946363343303041453037424134454531393042363341423435353735424443413942413844343932343537303533323234323043364234433845323842464333433931454630363935364537393732463741334231333644453544353543433723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x4c6a9ec2bdbde689c4237b896e4c93823b5e41b3ca1661d81728049c53b22c8d2491cfd34b0068954dfcf949d2bdfd5727edd3cd653999acbfaf37ea85e95206	1569819767000000	1570424567000000	1632891767000000	1664427767000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf7f48a4b6feb0e953c570197fb05086c99536fc12891f5f58128952ae3bae18f68b8d8bca88cb447812931216dc733d31f89fd4e4772e0250750ce4b92054fd9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304632304139313432363744423735313538313933394238433145343642433143453735463046443034453946444242463237433744393038314443463945333641464132353044384433374435383046444534393738443243393431364344323732304533303730323233454345363941373130384634373133384446413030383231343741353042334641324338464131414530453339433642343432413634353642463144324438444436433846383042363841423930373437333730394331333834343143364230383144333436423743313631373333433846373738443234343231304646413842314236384531333734453234463930383335453123290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xfb9cd41a8cacd4e8b1abb2c86b1950a49661b5cfd9344eddf3fd98c8d3750add5e38f9cc60f34b1ee85b174b1a5cd601a5ea606f474bfdf8930dc133629c690b	1568006267000000	1568611067000000	1631078267000000	1662614267000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x48b5dd6326a9e486d2cfebfbf360b1c5fe4fd134a45c71c7be74cf35a77ca268e99fd2bd20044a9e8f8d8f4925f67990942b25e77bcd3d69e32e19237a2eb6af	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304441303030333043424431463135384431324541333239333030453941343839373938343132333132414334333035463234453938393846383239464637433334333433393232354144444346344132313443333335453643354534463546444238353233383631343331454638394645383741364530423541353835453541433542413530343931354134464431323836353237373542313542454139304343424446443142423446453537394135434532303938384542353846314437334546384634323834393238333436383744333932384332453032414142384335323645443744333339414136334437323444304134464634413235434137453123290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x2fdb03a207cdd8ebf3d9f6b91cd6d99764259e0f52bc520289e9ca0e474bc9177ce32ba121b96268c2bc95f7da72e280d32b104ad5ebf52d557389b277f3bc04	1568610767000000	1569215567000000	1631682767000000	1663218767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6d141fa0ff3fc51cefc299f475f8c90662a2d0a0b01b5543f3502765d6e358fc0624c887631ef45e3c96348275abf0c30dbb0d1b37989fc03770b3c7f8e19c1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304637383031363334353134394634363544363139424438443545443135303445453143373439374145424333444630443235373434443537374341354432434235313430453530423131463636393642314633454538343338413031394341463845464132453445423342444544414130393344353838363244423045304433423041373646434235323434374430343437353730383636323338384638353831314530444442433545333430434445343246393045394644384336323843364330463342444344443839454231463744313936323842313132394144413530353230353632394545393032314242343543354636394330373239304342383323290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xb7e6f8078900bf267ab8e35596af047c5c554894613190e0e082e22657aa3f9d6f9882ae29283fb3c23bbc7579c90c7e04b5aee66d6ab9a2fdb7e3250741330f	1569215267000000	1569820067000000	1632287267000000	1663823267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x924d85e4c9a586936fdda227aac01b496e01a0b0c4aeac5b4be7e2995281aaf55900b22f012aa2e15e5e0741e3c66a158522a8c54441ad574f0667e4b4da791d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304631394235433539364238354144344645334332413641383637373133464443464542444235344133413633393735393931303335364235414645433646453332373937333930393134363646383330413345363531414631303833344438463035433944314536384630334542393743433436363733333045443143364642413045414239353842433834413341374543383235383441313935413435454534433439364232313543353145313837333634454339353437464544334345313746363744334233424643314434393043363441314239353634393842463134303346393036464131333237364446304339383644364338463838343130313323290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x11658c0a76927fc3b9e3ae18dfd31a367875be2a8fd6765e186b837dc14a937aecff5bacbbb37adeee4a2ec16428484a971daa865bc39e25f44e29a932ed8108	1567401767000000	1568006567000000	1630473767000000	1662009767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e74d7ea15f865d266b7e9701f7975e987e548abce526e7282b216db42faf930500256582df74fe711959fdab59b877a6e77456eaf12a824f006510ee7eb4176	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334463533393832433745344138414246383644343731364631343443314533434338364437304234343335393039393636384435324635463235383236313830363734334444423634394643344244424130343338414142343444333341413341443431393741323932444643373946333038333341384336333739353731443139333643454545343837313936344142334138363744424643383435363937363743463142423231343238303233454537453135333336453444344243423744334137453136303844463832314344303630454346303037333835434537443143353042413739463630333238333130423731413338424432383634313523290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x6850c3d0281c69214ead57b7017d2267bc51b7dc71c29a9f13fbb83bb94a834257e2f36d5b6f790acdf2cdb81d62e4bd89c3f29f9d115c5316cf23f9aebd360b	1569819767000000	1570424567000000	1632891767000000	1664427767000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x666744f1f0b37bf2794e4ad557d225fd67a72061385b55c56b325d8ddc773d35f0d62abfe736089bf6c97034e1e83e248a771c569584495311abcf52f4bd3e87	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433353046333644373934383142413233373236424544393136453143424238444430424644433239424336433845344346333137463232413732353534303746324333323437303834424237353938413933454533394444373437413134464236414638304139413337394145324237334439334343363746374132344145383931304434464338343243303138433046303833374245424343323137424343323430413633354643333446443839434234354232344337374333424543323544363039313630433433413030304536323841354631354146433932453936354133423044324346434144334246433837334341444335384132453445454423290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x6d3e73ed87eb78afb76e82ec348d8fb75c3a0b20ecd40044b462365b8d3125cc0ed7ea4f8dce09f6b4473e016b54f3b119b237620d343c00702406652b5ac603	1568006267000000	1568611067000000	1631078267000000	1662614267000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x641a25d9c6ab705b0cda2c44a0ba9a586be6ff60b2354a827548301b9132c32e0bb50497e3a459ed895ba638ea03f756022ee6a6fb99451bbf4d4499420a16db	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303936333734424145393938343735374433324344343941433736323633393946413743363645423443353530324130443533424235353137303233334131393831333643363234313033334344364242444235424436463835413536324437464533433642383137353941323433423037374133464632383037443239304142304633443437464439443033304537353545313235463644433734323036364638463244464333414533383942394439383141373944334531463039463335303441374330424332314632394441304145464137364532434436373835304630323441363237363941324336333342413232424333384445413135373245463123290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x64b3aea518b8346a29e23bdd5614b744d19d060706d2a8538f2a1a23f7f3d68653ab5abe2868543f615504b23bf1023822c8598bc0b6b72e1d7263b363391708	1568610767000000	1569215567000000	1631682767000000	1663218767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x385a130608c98f23e4a50109e2107d69a001108f1d3065ed377d700dc658e200d5d2236015853805787bd27be75aba591c27bc9b5072df2a6a9179f3d13a5808	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304141423839373945323742333033363633303230303744384436314537304436343641344146423142324641383442324141413437343234384534313635314438314634423245373039373844334537373944453244313138424331454531373445454444313534354234373942443544334142383532333743393132464342343531343031453632363843334231424143334437373142353539413937314434394633443041463638363446464331373845344432344442344336433641454144374330314538454430324144413734394246413539383743383838333933423835353936333830334435383334424439464445423837373142373744313523290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x84ae9c2a947945b69e1594d3474ec4b4d78c8891996659e812dd2c6dd1247bcf2569490dcd935ec45feb29c1a1b8a1c63d57e890819dc2a137ed5eac530ad302	1569215267000000	1569820067000000	1632287267000000	1663823267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdace75e05e870a847892690fa4ad28a8ca4057d00b05eab9957e06f19d7d8a4efca2eab031113813d97b6d5a66b12063793eb8e91972878c4e1fd0d052c55652	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304332363231383434353937343343424343374345354132443442393237334330343746303233344243424130423830433344413830313030443433463341343444413436324136323445313244323135434331313246304543413332313032453034313730373335353438323130304239433845453730363538453034304133304341423044374445313046324432443931453136314432374233434335384138383636413139394644323033343437374242454142343641333136433430443338453345434539363233453537354332344138333135383444444442443931314642433346443444393941334635383733414541453741373236433031354623290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x4beb6e615754da8dc07489ad7ddcc4923b6e1cbf308568efa79cd190e30b4eebd096a186854f034fee76738c4ac62af142d7aecea53a4454f77a89764a495900	1567401767000000	1568006567000000	1630473767000000	1662009767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa12b4e88b2f330402695e60c6bbf2813d84101881ecc12e9ef73ac762aba1429c91a2ed94bc8c6e2cf08309a8b6fbc423c5ebfec28da0f1ad49a7b26ee3b1b2e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304142423233433343314635433937414341454235354238424333334532434430383030383337363131303435364535304141443332434439393933453437324535423035413431353730443531444134433636444245313336433334384342443943433132454132464638333746374236393543353441354134464235373843373945303034413142453432303846304238414230343341363542463631343835453733384438334535433441303335363443354646313335434630383146313632324337444545344232423038363834463031453339433743443133453631414546354336454237464538414634344434343236324636424142424244423523290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x4bb419bc38878350d98780c193a2aa54fae9181a90f24c170d9d3079316757126527ed4146b44b88edf34e73d2ce81d241b5df9e02748b8c42b8e36d6514b00c	1569819767000000	1570424567000000	1632891767000000	1664427767000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9da7f29726893df1d8a12ab471bdb150edbf9746b88f7fabe1600a7f8e162c7284bbca2da20e9bf2aaca841f7ffcb77f0f4554a0f0817cde497bd6acdad369b7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304538413833393746334431374530423146424437383145463043334633423439343843383644393333373441334536363842363337383830354233303543304144374639433239464439343031414642463344443330334637303845304444423934384545383234364339344642423437443930374343323737393046353036383633344538413842463146433835353642423833354639373331334546413442463034314246324533333830463231424343364431343339394130423346353836303832373230313144334644423946463345333637363431453933304636303244353545443443453846333442334344414436343731443646413938303123290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x7529b8c39d5e5ae1f63cfbae625917a0d64c3083eb261a680aac85783d6c3991a624965f5a9efadef8ac3edacf4024d4a9ce82c972d70b7c0c86ca25f148bd04	1568006267000000	1568611067000000	1631078267000000	1662614267000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3e1fa208f579273a15eef95d358823faba4c1b00290d5867300f5d2868e4f61e80e4a6ffca36590e2a0610952f0c61eb6958bde664aeb71268c627785e72a48	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238384543304141453636304245424536373943333742383434353636413243374233303539413341373932313442463433443038384145313636343536393543393637464138303733383544464144313335363345364641344637423741353445434539413239324538434533324343454435354245393946373838443437464444464537413136373436354642343145394644323546353744364230303935434145314146374334324442343045373333463741323341454136443334393833324530334132443341343338363842353144413730384532414631364246374333423032343838353831334130333035453143383443384342354544323323290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x609dc6ff1a97ff575739684d6f026f32b4a55ecf176ccc52bb42de8de3ce6d988abb8b2736e1abfb7f9e507aa5b37a8fc0abbc1c374f63f149660199c0802f01	1568610767000000	1569215567000000	1631682767000000	1663218767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15f27171fa4ff808a40d4c2c75235db0e395f45e731001c3255843f1d015a2b4ebd2315f5e6c8568f7efaa8b1dfb567279104a541a107024600ffb4888102cd8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230443441434630353144413735423641303133394445333538383438384232353145413830353934434434453832323944313833444430364545333034333534433133343233364335343533423143323444343441343943313738384136374131363745354434383431363632393435394632334643423845464242454645413445324538374633333345394331373539444133383230354235333531314634433741423946443641343731313135324536464430374545463441333634434432304439453131384443343942454531443131413138313643373335343334353432433636333441464237393432454639444332323738383235324144373123290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x2b000add2fa88324a8518fa60b9fdc0cb312c1d9adf789b78f97d995be05ea760ec71283f1b4f0f298632ae420b41fa046e88b3ba3725b1de066b0bca622d20e	1569215267000000	1569820067000000	1632287267000000	1663823267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x726f628271356541be7d13929b466034bdc67e5457389305ce7d807445c5398c2e009f5184867b689b246b9f539a6aade976cdba6b12eda47e2a8c54f4bc86f4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136464246414242434330463839344437303032383035364131304630364243334444443045423932454546434436384145413943423432353730344239393338344546454131344536374642353146464138313638343543333334323331363039444537393937313835333435434543443630304630333146334333453043394444324238453242323436383745323145354538344331334434383338343234433433433531454244373334394434373244353846333141364430393334354536303644324337383234303136443832384231304246364631364238433736373243413237343745383643323033463839304344424446424638363338304623290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xfba999006399b107d6cac14fb120d7d19061b663cc4d78c99e8fcdd086e8b49f2fa3feb5ab8b7a783ffd50f70f235933c98b98f20ef784bd68867ddf6f07ba09	1567401767000000	1568006567000000	1630473767000000	1662009767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x902ac9f0d3d433e68a2ca8b086023fdef6eba959a889c017cf43a92832ac00ab580bee27c38389d2735f24abbe8220ff0d7d241f3435440cb4f1cdc83b9bec74	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304531453638463532453835394431364434324131363334383731334137353745344230453944423144433242444338383242333732303339373836423432454531394246463542453931364136373239453139453736463735364134463144313442423830364243384542393442373633433634453737324532454636353745444234364134394435324544323332354145453831443642464436464536373539453446354139464445453835303439303238444445373233323831364533393534453938313146423835464533463831313838414436413544453741413634334630383235344438383933424633433531303036323134353345434339313923290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x91af481c3770218b2888a4f9e05ddaf3b3ec79856443197b14f5e8b636ab03136b532ce609453b561a5b20216a82a12fd854fcc93660047844ebf85b84d1af0b	1569819767000000	1570424567000000	1632891767000000	1664427767000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbe01339c22de6b0eff23ee5b2e0f90f31d976c9ac4d70b0bc08acd08ae3d87a9aa5ec17ea4dffe98445ec4173b9bdd7a8ddbdac824db41fcdad91c2897c8cff5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439444437353345364342423633394143333044333742363743433943383736423344423837393943334543363246444246373637304334314335314632394537344143463944374336373644423232413635323736383743453531463135303045344534413841303643393643354242333444353541463530463344373245363832323743374535374433364539434334423038313745363643384242454644354633364439304633434436384438374631463136393845393537383531363933433037323141323539433635313443424346453844364343373837333536313943303437393035363844313137373242423035464344333945373341333723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xb2f748e073ca0a2c56999b06492a27b9a6b93569247126a248ec0f78fa383d0664f32b65fd480af0cbed0a08a762c92d6bad37238eb633790fae995b885f9707	1568006267000000	1568611067000000	1631078267000000	1662614267000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x821903efb945a68897662f4ecf1bdd13411b300642d7528f3ffc98629ad8a5808dc18728184b2b96ca4952679597a58f9a551386ac19feebed8317733bc17faa	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304144333135463241313035324544374245423737373542414446324643314246304438344330393834323845444336393338433336443946414534363246433135334634423341464643463539374138443141384138453034324230463734334530434241453539423838393933303332443743454633413132373745323034413241433735413237433045313430463239363030383331443041393142364636433933384142304537323232463442413646303331433632343633453545363644413745463130333439423332374337333436383435313143323939423134333436394245343546383035333831324336333544393233463736463230363923290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xe3cec2a6ec205f0bd5c54b0828f0ea863e1a4aae4406a44e086fdded538add7140d0da8d12e1f29eb97eb1c8ee6d38da18f781b888dfe77036648996f0415a07	1568610767000000	1569215567000000	1631682767000000	1663218767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc281e7659aa00bce42affe1c658326c8d348caa5f1781f16d2786aea07bef61dc0ab692f233873dd698e1614d6fafd64080130600831f30f7fb8c8bf103024c8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303935363537383037424230464234413642464531384530313137383844354445333634303945313337463041363546374433454643424442313241374137444231453642434637303946443337414338314231433632383139373044393230313832323846323833374546304232374132453130343741323942383442453930354131323736303531413832383646434342383546363330463636373843444138423643364331314630384339313537444532393934434138413131433936304435344442443739373236443841323643334331344336303939364531384335344545334641333544454337443143394130354138304346314339343746303123290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xd2dc737e7656f196fd711a193e886e5a5c6cdcb0e13cd7adc7121ba1efb7639b1272e4aa6b4d71905ed10813e85e55f8cf34683eadfa7eeb9c5b71b0de330500	1569215267000000	1569820067000000	1632287267000000	1663823267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb825fd04509ad584bd348662c71e0261325ecdbb6a53923f76143af79a2e3ac03777c3123dbdad2613777b4045090f1036449a5cf67783826fd22c5e42fe58a9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304142443630303834464344393239464336363231433541333538394238414334444434414635394441354242333234414341424531353942413736424641323845354541453634313643314336344242434141453432333533463031393638314445303938394530323142303338443541344232423835333542373436373331373446303133433642463433313846333438303433313130344330453933333246314343434338313135314646443534423934373844364635364541383833373138364239304244313042323942373141433644463637463434433431424337353741433246334230343134363738373841383533323939394631433645343723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x6f239f6f6d32a232147af53a7768f20584f7d0e514465a4596e0d104350803dea0398c94b520d65b9c780b46793e635a2e7da3b8c074861af8f3cda5ea6f2f05	1567401767000000	1568006567000000	1630473767000000	1662009767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x007a723989d0fbe8ae2e8213897d795c53b898d820b4184667f2f75f2758c65377d5b64e3f041caffc8001e52a347dc03a8d74a3a5fc8958fac4d3315b979a9d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304332393437424438364630424544313446364435354535343236413631313538423843383643413936353044373830424246453530414442464432453432444344353033373546374633463733353543433144443237413844433635434642443434453838373541393843363243463344324342384439364545394136384141444246464630463338443144394435424233434545464130373241313332433434334345414238433838304331363942343234383839363632453045354334313139453842353932423141463237343434443638394638303538423241413730363143333246413631303538394234453230394336313831383244373144333523290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xd954e66c6767a38713bf1d560bd4343a2e6176449bd3532b843f3d8f3c3098ae66aabd3caa84a61d1f20ce23c456b8c3299ae0159c75dd0a60fa7f89c0e5ca08	1569819767000000	1570424567000000	1632891767000000	1664427767000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd0265befba3dddba12b8e6e7c5db1a855b291d5466f27f102c73c89b911f2a786728a18c25c76e1e1423037f29524f084c8389b0b3a3857b5ec5f2e78ccfd302	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304445374234343345454346384543424443424230323346303436323038423135434431434532363534304642453346363233384434354333463239303642443430383941353934314331353232384643323346444132383733443142373734424138314232303237324336364639394330323931364142374241463935454130414536433041343536414537394245454133333443353242394331323843413232313543463539353238433246424346443935434243443444353737393833383035424241304233333743313835353242313445343245353241363843303634414235463444454139423637313732433834363739393536324230344343364623290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x71291e3b36cc25dd7cfada33fb38d997a41348ceae5933849013dd032a42e9f769faf7f0997c8eb8d1c5f1ddd09888c2df993b3cdb5c4aaf405e248dc3207607	1568006267000000	1568611067000000	1631078267000000	1662614267000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcabe8c00d56fbd837d1600f8d7f1683da3c3c695c37d9c6f132629b78cbf34a845383e929b71d95103868ef8f197cc5efd3b9f917e4055067f8bb13307007027	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436314135373444453345324542374635324233443831424139463042383931414343383444354441434544303334454239333536323642413633443434343041323634384437363739344341303430374132333631303746303933414638323444433331363536433246383345303839363335334135313739343135413143333438393644363545324430434235443033373031423734463636364138464343323530374130304534384138363133303245303830423033333137363735413245373441453443344139353044373331344343333245323742464638323935433636423245323231383241443430373736353431303042453136444634433723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xe2767aa0a05ab83f5a9e032bfb0babcef3c6de7106ff39318091a682a68f36c4b67550a62928580ca5a39bc97d35e4d2b2ea748b38906096617e7a38b5e07409	1568610767000000	1569215567000000	1631682767000000	1663218767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1f29731d3b4d166e9318be634e33042ecb26c9c5266d7eea13c8b6d299c31c78e28138dbbffe51c4758b8408bd89898a49a7f840f681690d050bae86ef068368	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304346373631434335453941353831424630413541413837353445344535384544314230413733353344424242333944413845343334384441434533354446453338373645463445394234323431333738454132374246413432454642373845313846433445393142434634333145394444383845394137394244363143413942313945353541303738373638343141424544384334384336343344303530344636454231434336463545354432383041443146454531303441464242343431313042414236343732383845433343364132333638394431344238373237444546313033364541393837383733333032343342463932344439333742353546313523290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xd343fa07c0abbe5c811a57472d1878754c8cdd451fdda665b7c19e712a8640984c35143ad1c938c5a171c1a71c79a52a35af370d09ece5ae007ac27adc476500	1569215267000000	1569820067000000	1632287267000000	1663823267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x677d96b824b244e6a62da32053f67cdcae36911338b5864eaa8d5a986ca2147f8e4e3fb53b6357f283086509f1016d9d1f390af40de5a186e6e73b1305bc9f96	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303938453343413442394333313534443931454145383131433336313642314535363730323437363234393233384637423344313531333737464535333533424634353335433245443237383537423834354641413033304139373144383546354436434433384343453941454135323335414445434142323842323941464238373535343432443143314545323246463033304431414335373531443338323341373138423135303738464344313339384536303635374137313438353041334344454239363637373235303236394638353445413532344242393933364539434344383233363834323136434542334342464132354641364430324138434223290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x80243ba5a4203fb6cb1a0c046bf8c240b3beb0374ac24b4c65cb6d64f2557dfd679a906f559fbefd4448e3f1a9cf776610377d4699dc6b0987a49fbed2cc960c	1567401767000000	1568006567000000	1630473767000000	1662009767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x791ae36b3822806b77abf82313e83137aefdee4f0db863a2d5ae787c8c2cbf5d3022ff63bb7cb41ec877143addb478915906823d80c934b0fe02217dcb2bb0ed	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304339343241364631303833353733314336343045353132373242303245394539353830344137463136353631443032303543333030304634444446383235373333464641424432304644313243314232384444393339414545463445464345323641443931334531393143363636304137444235313836413034373231354536413634303632413233423932423738374646443836314431413633303541323045394130373132334243314543443046344335333446354545383237413134434131343433394238303939444233373738303641414234303839444134344430463337364243373632354430413730453535374342413334383846414435423923290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x4beb542efc9e951addb72c2250d70fd080f0a2a5cec4d30aa1a6fa08f2d8f6f772731fd10670c6dc107d28e76447c7ba2dbc39e4747dada598d0bbf283940f04	1569819767000000	1570424567000000	1632891767000000	1664427767000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x21ca925499d96506d830120ff6987e1793211ce5d37709308882ec1c81b6493deb499cb842ede6132e3f19b9f7942349a2acac8f5f73c580732052646d0a2fd3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434363434453133364338443534383530304442463541424431384134324441384242433731423430453738383830363246333333423336413638323031303636414539304433363533463339363230433134423537463434344633433639324533354244333138453743373632433045393133323343414642454630433734324639363036384143433238414439363532393045453842354236333146354141313341413034324430314538353543414234353739333134374436373141394230323037364246343834424431383135383742454339373342394143393942363438394545314133393942414439324336454642463136333442323935353723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x186ec359cd24287d9c0247453b689550130e1a5464abfe45a704cae0e44dedbded825031d99e26f0aad254c7c3a466465895fb7f4d7599240e45fa18c473250d	1568006267000000	1568611067000000	1631078267000000	1662614267000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd88af4071eef2f57ef41733d82b47b9e6e1842f3a83c1e9113f6190875243027903b3d8a3dd65caaf2f40da82cba1e7e925c9e5d457078e76e4f2a982c01cc83	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304231323133463443453439343533463930443743423839433138364346374535463239343245354531444637334145443246454630434333333535463539364543363341413343384432314338463338343631333436364441323146303744394646324534423234383941383841313430304443364535343737324545363234364638314231324443314633313638333641393037353446463631424431374139323836333530324437354346413831314534454633303643384639423542453942333536334542313842344643414345333043443241354241383243363933443937463645444644304132304146313930413633453441323631323041443723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x4b2e630cafa41ceccb809531f3e8415f220e3d259f6d9d659d79aeae2ecb5b27e13ebaf011910f9e8241bc11cc4ddcd7a751d0c342f8a13d229f18691e510d07	1568610767000000	1569215567000000	1631682767000000	1663218767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfc0dab248c3765858040d86959247acd41e8fd63de494a52bf18929e9008768f39cc901aee1c74ba8bc51dfdc2883d6ca9af2064b0cf908edd2c0c656097e2bc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304130384139393537423645314635303434423631383442453246423836314232424635444230463831353130363136393730393241413241454641333632444331334434433145353239423831364341414646353035454638423234364334433141443246463431443136313942444132413741384132433034303744423138333731393930393646423741443239353446454335323836374338373339334431463346463431374642343335464644463444353446364239383037363542423635363242413439373934313134393537434245304330383936423335373245304231444531343343323337374439323732363638373536413537463441324423290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x34d13fd45ed621cb43a46a44e526cc412b4f6b37a19d5c546a77a03a3875e6b9f7c3a8f035c0c2fa1b70c966a204f32597e1e6d3189cbade0f1c54a1bed4010e	1569215267000000	1569820067000000	1632287267000000	1663823267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeca9b71e64b6b04f1a93e2e4f822f067019bbbe86df30fc42348960939cb109fd89cf006876d778799c04d70e84d6209dc7f23ef0ab855b8ec85fe7c0b545317	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439373946464442464230363836333137384637304333383337383537343438384643373541303642313430373146344531333537453636463739394237364532453838323441323432334537453532393937393135303036364346433638334138443338383946304230423331463032343745424334374535443337453734343432313732324131463445423746343446394337364233414641334642463537364636433131454536413137333631343630444434313134313145454437453538364338353642303732324444303237424542314230373132383935423145384441354646314143443034343335373844323443353545323935384533324423290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x130337cb45245c1300773790c6e26bed9547ee887d830e27261ff44b7bf209b0039d3edd34b2e95e6cd68df81e5194dd9696a2c3464bd8266382c3024e9b160e	1567401767000000	1568006567000000	1630473767000000	1662009767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18a914f9f1e9a639aad95c40b36a704ca80233ac15d4155bf70b5c98a5373c55f205edc09d32887e768225b1570007bd76a6238033780bd7984f9ca592f5e646	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331313442373532464641303345453642383039393644444431434142453541443635343141353936414444463331414237313843333741393846443036443038363338344130373945334441453238354344324438434345444339363338373536323535454334333339304243393738463534433738413944423835323931313234314433464333464141453532464435353236324433344534464534314431333131373233383238354631363736413641413735373443413639303541464137343041433432463432393638464144363335324131353832423138464439443336443836304345453535304335384346444245373342304446353342323923290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x206ad671d83f59f5c492a0e603e4e1bf25acfc053961866cb4df4ccd89f7ccb72dc21e2f456b2befe55be6a0e6ba74a6495d47d329e922b9c9658a31b7dbf101	1569819767000000	1570424567000000	1632891767000000	1664427767000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xae454caad46f61439a3de1b8401c249fb6481a3c2220657984d263877aa73d25f94e6c6b2599de599bca98250cac629b8e653c0b8107aca2587a55984eac20f5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243303644354637323642313935323141383130354641443233463338413239443535333736353436464244423832374638414145344332433330413536333730454539463034334346314534354433413236303933364439354635424545414434364130323139453441414342323530304543324535373038334634343442333833304436393437443039314139394336313437303736443145443639344133363036453338373135444330444434363133364230393945394144463533323041433235363543304337333446353539463346333434423736384431363046383242463344324441463145374545414537393832413132384137423835434423290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xf90ae315824d2eaca3c05ae390d63a1271c6f26288d7709516377370d6ea0a9d51dde11199ffe7b7cdb3b0cba5729523001d51ccc8e0b634469c034ae240050f	1568006267000000	1568611067000000	1631078267000000	1662614267000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xabb7178037685235262109bdf864976786468618bae0bb7f6686d18836a862d80ed5f669a07290bf78f67bfd40285c2eeb6cd2849fcb9d1f5a2dd3b5fb3ed30a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331443546353634454634344532424430453538313731354435344339343830414134434131373644444235433146364246354538344445433431344332334645364239433932413036413044353936423830413332414346463032393646413138323643323837423533364141463330343835324141453235363345373435333432304133374530413233453830433037443144313244463433433646434641433130413832383039383045313942433337373135363445363636414633323530434444313931443835343345353243324231453936343138364139414537354533423036384338363430383542313343414544343741333132463930363723290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x6159f326b7cf70637a6db3a019780551e37a67bdd3853786fc896ec17e735ae0fcb4d756340d76c559f2ce42ba43605f915b05120ea1c0c1b8f84d5290409e07	1568610767000000	1569215567000000	1631682767000000	1663218767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe77188f6ad4fb2c018ca1c6f55d6005e40dbdaae6530beb8bc28ae47bef61df1619ded2f5b4f79a65766163cead34e5b1b0674e6bdcf6e35f3fca6ae87df9999	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431373946333342364138424130383133333030314237384633334638324543304546364230304235334644303030454345314642343532353539453843373236323234314632313443434333304344353435323937433836453941393234303630314639463544343931423933324441303042343036353146443933394339393939463337453445454239414233374341383345393136324441323032463642344146363345413637454232344334433645463334324338314242423546373133354534414446444636363345353634323731384537393932453231353432303332343245374142413432463935453735453631353042314145333134374623290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x6adf7d44e4a275dee1a44ca100485508c6b3b312e027490ae97056900443abe47a1df1cc0ae22d3368927f5358c06b8164efdeb2c01e3d139cb08e8d379ceb07	1569215267000000	1569820067000000	1632287267000000	1663823267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946313931373045303943344639433846423330393945383234304342453031313430354646453741393830303432324245424331393046344134364130313945333830443245463245333838424232303646363731453943414542434141354138463430363546453636353237423745413336354642414333374131423041313131434330313939424431343643393839383743363131354236363235453931454446464244414135364332464136383846393542344145353946343930334131344146393137364345394638414533353634363038394246324239354145413844433038413937373043373046384536393246343838343534444336303123290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x28d24a3d5d3325988e8ea30515629935cbf492f8f3fd1a0d17421db7d2cb783439f208f993c0dfd263651a997f6aaf92adb3110adfe71e66747d780829e4d40c	1567401767000000	1568006567000000	1630473767000000	1662009767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6bc31a9070e85f0e6ee6b198d9731255dd0c1a54595cbb87ae4803017ab6dd6c2aa6843376ee85cf37a9c43ba9d733d1e3427430e53f651abb305cf6156d10f0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136323733323143303836353844463930393433333131354545393036463043433036343141463333353644384644433142434132384634363243323539464546333645313945463535363332393444324435453934444336433835323433463536304241463233383334364232413137304644353735333738444133343241324342453632373844393831324443414131383436374538413042423139323435373941364532383642464135463332353044313733313845324339423135333046344439324338413038374445333942314431364138323645383746324439304443313035463046433341453142363130343845423537383532453130423323290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x7786cbb0f11b373460045b23ee74e59badd0c7fd084b1d6da39e565598fac0977772cce23d9204cea9fd31c0bde414832b23efdb09a76e2dba5706218c9c030b	1569819767000000	1570424567000000	1632891767000000	1664427767000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57971cb25fa3351c0c390140d146b07d02960e0e6b848162da12627433db6579d56a0aae712c848d7f9af6b866962c106da8b696501d632cd4439c3e3532ce24	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304339324535313837454635313345383531303246323942393136323941423735324339373442334236434642363335454630364546303637383133433446383737453544414136313738334442384332434433384238454544434642313038323641344645424242303432323145313442383937393535394237413131394230424135323731373630373235443843434444433938453143383843304131383346454434373835423334353236444633453434413843443531354637433437444239344332313342313136433634454646333144413437433546384436303246373641414241443841444431363745423037353431313536334643423330343323290a20202865202330313030303123290a2020290a20290a	\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\x7a87a896219c959ca29fe13c8a494e6f07a1897f11bacabf5ae6af9fb7cae60f40e2cb8b3ba40fd55ae9dfeab865fa7efc5060150d3afd42e7c2f00e6c22f406	1568006267000000	1568611067000000	1631078267000000	1662614267000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\xfdd5e267d8ef5695aa5e0d4d676d0f7d5fcd1efc9e24a0a57078b22edecc08df	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\xacf284b5b58a9c2b9a979cc61177cb717a07c35831c9c3d036861b79805ad54982964708d27ac8fae9350ef25ac823167897fc4462c0cb6212684f0069055203	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
2	\\x2d99ba10c9df3a77c7df85f549a1005c7247cf4bcaa7c8f9ce1a01190ba59102	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\xa84275c8ca7fb3efa79bca251a181c232446a87da3ab7b4004f364fcea1ba40f9e03b12a6c8e5db9f00ed5397ffea16f142e190ac7cf2d74839e32dea0b0fc02	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
3	\\xc4e5f4dd5c7615e07864ac085f30deeb3dff6c5b2101debc36c4bdfae27678cf	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\xc7628c0f8e6452fbf3500f41c35f50bc47e9ecfb45b081ca4bde8af491cfad17ceba629e597d0a69181a282c325ddb5f289cbdd9beba29a4077ffb97e11a6e06	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
4	\\xf0a660ff31d88dac12a465b49a6d0020231671f97de86a52caaf4811603ac301	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\x1fa92daf740b39fca04eaf8a55a90b4935864de79822868951735646474553a15afa17d10fede163ff5725929782f4e0260118ab68b7bbe87b044e7524f9a30a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
5	\\x9e0d75552335a39bc9224b1d2ff872ac95d69361255f11b881192c169efaa989	1	0	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\x6e1a45c1da55fc3648b8bc53792063103ceacab88725638c2e1eb9a043d8cea0f34c5a65087c54bb57e63b9d11503136ffc54f27e37471a9cf4e35aa3670aa08	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
6	\\x2e416b0a56a18c0e4c05033e7e3b437475b5b3e472fd20e633a184790329a75b	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\xb7d15f93bba0c95ffb2f3c84ce280b15f4f82a7b583f5970e3e7a6ba47c9b542876b756c3673cd487541fc7a8c39e662aeaa0a6f0c82dba6dfe74af3df4c820f	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
7	\\x433942d093b08b1bc3accd1ed78efb2291adf2b7804461d6c50eceaa58a9baf9	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\xf13a20b3430362b22bb64ceca1ae7c0899e0add35126305d515006251ef45d2f560e8f6fdae8758c8d1f1ae1ff13a68a703f5cafc1a4b8853aa98120b1394205	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
8	\\xed561b2ccbb208bd4f31731f9f197f4fcf5ba2416a692d7bbed897838aa2059b	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\x8bcac864e662d39a58f2655ba28f90e0343af4821165cc5bf76619a760ab6fcb3434273e985cb0b9a3e1209e333029fdeae7daf60daf30ebcae57f973e474900	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
9	\\xf7bab33f31c959d9364f9ecd866cb2ee8351d54e5b7ce5901265efaff651749c	0	10000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\x80e5f92575b1e1ed78d813d2405f6f7aaafaeacb3a16708ea8404ed21064fcfeb41cb6b0aa533db577a611378eec647beb9f0bfab53adbe3ae45ec4a3404130a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
10	\\xeb9f7928d48304f16e1b59a9b86ab4e1fade8a4d8a24763b1acc532b5d7db530	3	22000000	1567401801000000	0	1569216201000000	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852	\\xf8da40a6b598db5195171f9325972cc172883eb2408751d1890402d0b8f80e6c3fc11694913b61c66b8a3646695d868fa6c01f6e4e98e361787157ba771ee500	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"ZRP2B3EZ2Z4X1N1FY4SKAPAJC0NARKPEHDPY8X1SDK68QYPJ9KN80G58G9M0KMKH4HZE2S38QS43GG5HPSYS8RDZ4192600CG3EGZ98"}	f	f
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
1	contenttypes	0001_initial	2019-09-02 07:23:08.904105+02
2	auth	0001_initial	2019-09-02 07:23:09.750832+02
3	app	0001_initial	2019-09-02 07:23:10.285456+02
4	app	0002_bankaccount_amount	2019-09-02 07:23:10.294374+02
5	app	0003_auto_20171030_1346	2019-09-02 07:23:10.305861+02
6	app	0004_auto_20171030_1428	2019-09-02 07:23:10.317298+02
7	app	0005_remove_banktransaction_currency	2019-09-02 07:23:10.328734+02
8	app	0006_auto_20171031_0823	2019-09-02 07:23:10.33955+02
9	app	0007_auto_20171031_0906	2019-09-02 07:23:10.351049+02
10	app	0008_auto_20171031_0938	2019-09-02 07:23:10.362023+02
11	app	0009_auto_20171120_1642	2019-09-02 07:23:10.37313+02
12	app	0010_banktransaction_cancelled	2019-09-02 07:23:10.38435+02
13	app	0011_banktransaction_reimburses	2019-09-02 07:23:10.395026+02
14	app	0012_auto_20171212_1540	2019-09-02 07:23:10.406471+02
15	app	0013_remove_banktransaction_reimburses	2019-09-02 07:23:10.417658+02
16	contenttypes	0002_remove_content_type_name	2019-09-02 07:23:10.472708+02
17	auth	0002_alter_permission_name_max_length	2019-09-02 07:23:10.49586+02
18	auth	0003_alter_user_email_max_length	2019-09-02 07:23:10.527921+02
19	auth	0004_alter_user_username_opts	2019-09-02 07:23:10.555203+02
20	auth	0005_alter_user_last_login_null	2019-09-02 07:23:10.585562+02
21	auth	0006_require_contenttypes_0002	2019-09-02 07:23:10.594785+02
22	auth	0007_alter_validators_add_error_messages	2019-09-02 07:23:10.623991+02
23	auth	0008_alter_user_username_max_length	2019-09-02 07:23:10.706525+02
24	sessions	0001_initial	2019-09-02 07:23:10.90698+02
25	app	0001_squashed_0013_remove_banktransaction_reimburses	2019-09-02 07:23:10.921735+02
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
\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xad217777c6b9bfaf57834751f096e8680d63461ffe9f95940cbd71816d17750d6b55097ee691a671218ca576e76f58a827be05f044c840d5822da6b42c6a6406
\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x446575db0aeafb7275af82761250acdbb65e4380e23ecb93ae6dae90c3d2608a2969c88898c1200b5ccaaa411b52f831a93533bd92c41e59f54793528301f70f
\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x9ff6c1bbfafb90554290677f328289d10c94952b4c1bb0bcc3bb44e297dc2130540f2e412f180691d6f0526d00242776fc96f051bf1f038503c4a5285c07890c
\\x16d6ac4ee3bb165319de5a67712a58f6409addcc46935732ec02be93a326747f	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x3becf6a669cf255a61d57090a82f123094bda00030ea01d49283b408834a9bd580416ee8781fc692acfa92378f30ef86306d84e981a9c073abe9341aac5e0a0e
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\xfdd5e267d8ef5695aa5e0d4d676d0f7d5fcd1efc9e24a0a57078b22edecc08df	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233542383731423743393036444643303442424430453039353246413642464132463537303139374131313437353746324632323332394644443146324643333445393939413336363430334233413133324444464239413833353833464536354442374335434445304441443035374438363336434541423834463843323843344446304144363030343430413038353435363039373833434431333239393736423642433437313041324632414132414435413833303432434346314139464635394244434346374436323238344143354544364131373739463430353032323241373838423837363535453434423145443831364244353638303232413123290a2020290a20290a
\\x2d99ba10c9df3a77c7df85f549a1005c7247cf4bcaa7c8f9ce1a01190ba59102	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233132353635373139413732363833383835384533374245433135423143384342313845413035394632354646333032413943363037304142303730423144433938373539374246424646393331313337383444423338363039304143393044303445463342384343463945363238443843413334373142314138334638423239363834383530443141303837324133313539313433383442324342344345343531373735323936463936443236374131434137434244433645333941383536334237463632314238383133454442424435413737363437413931343141364531424643343145424636434339384642463837314530323538313437413130303323290a2020290a20290a
\\xc4e5f4dd5c7615e07864ac085f30deeb3dff6c5b2101debc36c4bdfae27678cf	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233536424441393333303530393337413344374534333239363545373936303745454345424545363434433943374333433833373230433835373233433443433730374638313231314539303037303944303844383136374432353137363330314538383245343546314432444636423535314530413638373144463336373936463130453339304139303236464439463530463044304637443443334130424346414537364337324441343143414333443532383931334143433930344339344243323839433831413330423444433030413231384637303241354542393935353141413430444533413041314137374637423031453141454334363535383823290a2020290a20290a
\\xf0a660ff31d88dac12a465b49a6d0020231671f97de86a52caaf4811603ac301	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233233324241434445303730314137443046333933353231333137413536374439454543423132334343463944433333374445393742433833353531453235323738423143334242304138363134393145364531443641393546334333333830384338414230463230433631344342463245333936393937463041374143453446354644373336354134424337324430374342453641324538453635353738374236324645323441454332373641314132323045324143453542393745414634324646364431424543333339423736383135454235373841383741374644463630463335433546423236314346303739453439343346463844413839413336433223290a2020290a20290a
\\x9e0d75552335a39bc9224b1d2ff872ac95d69361255f11b881192c169efaa989	\\xb825fd04509ad584bd348662c71e0261325ecdbb6a53923f76143af79a2e3ac03777c3123dbdad2613777b4045090f1036449a5cf67783826fd22c5e42fe58a9	\\x287369672d76616c200a2028727361200a2020287320234130353233363943313339393332393037384136343334313042414335423346463445373432333244414242323232324242344145303841453545304145413035443631423643453043413335413033383233373942314236393339393339304243324435313945423736343042413041354331453841303945444245354532344346413845433346443834373834413345464644323633424535463543353630364634394332313545343046453541374643414435443634433333444436394637343937313944313344443235463331373031453942304135434444453944424144453937333231424636443537443344354335383936384131313837304523290a2020290a20290a
\\x2e416b0a56a18c0e4c05033e7e3b437475b5b3e472fd20e633a184790329a75b	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233646373646364539453132464243453838343842334334373546384638334530433246414136303533324343383032464231333930444336433937423037413732423936434133344239463539393231454435464232324430383935343138363135394232363535453337453530363545323432304641354344333230413537353538313445324642303433443935303532304545303241463739363844334342343245354345363146323137313241464335463836393537414234413839323938323532423332344642383030303535424530344436383432454445423645343038423244333141433645363633453434344131383533383241343438353923290a2020290a20290a
\\x433942d093b08b1bc3accd1ed78efb2291adf2b7804461d6c50eceaa58a9baf9	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233730303143364238344637373535303532423732304431413633453443463445423935384139424341364536314643353530364133304331443936324245444446364530343635423930353741394439373432383741433543423834434343464242314436363735373243343334434146364233304236374630353236434435324643374531363436313233343843373035423045334243304642414345354643413836393342433434433245333530434536394635443141444632463433414536333544314645434339324238354138453542444338444643423532463539413230463336433446354141343534413335433334313539393230394241434523290a2020290a20290a
\\xed561b2ccbb208bd4f31731f9f197f4fcf5ba2416a692d7bbed897838aa2059b	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233046313332323930334331314544353743313339424633353546433736303742363937383734393945333541374336364235303546313444374342423041334546374143323539383532324430354130424244434430304343353845364337304230373738454531434342323033314633383131313138313241343441353638413932364532324239414238463839413539393033463236423938453635343736363938414133303136463642383635334341353041434132303637314638424632424339354638443637433639463946414332453337424138434435454245373039443245434631363945333346333941303837334242394131304130424423290a2020290a20290a
\\xf7bab33f31c959d9364f9ecd866cb2ee8351d54e5b7ce5901265efaff651749c	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233442354135334544434236393441414539443446373835303343453039313445303333413445333442324638334139424636333238373436443639384530444635323944353933304342343035393836313333354444313431374641303239333135414437464634383443454630343439343245354339344237304232393731423831373031353439454543363536393042424535354245454246384335303546454346364234414444423246304436343830323539394330373637334246373041343141424241413033464243354642434146444430463836393934444346354241443734304330384238344135313238453244443832333034324241353123290a2020290a20290a
\\xeb9f7928d48304f16e1b59a9b86ab4e1fade8a4d8a24763b1acc532b5d7db530	\\x8a5aac29a01f36746f2baa61c818aace568f453ccdd4cf13442b4e94b9a1f6e7f151a22e0ac4b112517c553981a39e114551ceb2e4408e75262b31fff2f1b7f0	\\x287369672d76616c200a2028727361200a2020287320233246463633363539363842443232314539413432324635323143434532434342444536413044374645344132424146393634464437364539344236304634333735354234353538343543353332374133363341384634353946364138383842424646433541434439383137433041363444303534393136333130353133373031313035374241443642393535323645363131304336353245303345373135353739324443374442364236443238423935313139344233323344443934383544414439384545304244453333453841433934424346334236393236313034364644434244433033423837324541374537303744323332434142433232394446324123290a2020290a20290a
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
2019.245.07.23.21-0395MSETD2PK4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234352e30372e32332e32312d303339354d5345544432504b34222c2274696d657374616d70223a222f446174652831353637343031383031292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637343838323031292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2232564241524b5133514342353636455942394b5132414a52595330394e5145433854394e4543514330415a393738533645485a47227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224a575a35354d434b4d44425338325a3958574d4b4b474356304e545957343831594d47524847593033503830424459514151315346543936344b523953594b474a34324237444a5030515a3532433639314e5a31505a5133315937574157374b4b474242474d47222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2243514d34484e3748354a394737594a4851544d454e3137323935303334575350485133394a574245433456363246504534414330222c226e6f6e6365223a224e324a4a3852425736305837575437473741525a424b424a4732323658335a4b4248483851564237435952514144435657354e47227d	\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	1567401801000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\xfdd5e267d8ef5695aa5e0d4d676d0f7d5fcd1efc9e24a0a57078b22edecc08df	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22564241333337435a48313844324359415454455438485a4859535958505248474d544b3658433547345654305a394443305050504d5257585752564a5938534e434b354d4d5a564d4d33525932574e58464447374734365758344654514443424a473536383147222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\xc4e5f4dd5c7615e07864ac085f30deeb3dff6c5b2101debc36c4bdfae27678cf	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2257425343594d523454334d51313434464b4b3932385831305a35535a31505a58314a4831534b4b48334834374437584834564558424e4e475853484e54585335375241544b4a344739524b3048384136465859534342514337563435574d365a3231354b323030222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x2d99ba10c9df3a77c7df85f549a1005c7247cf4bcaa7c8f9ce1a01190ba59102	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22333359323138433444363639564144484353535952364e41505754335746463852443035464b5742333548393332534d52335346584857383157464e4d4744424e595a4d30305450325738384e4d4e4d54324837354430394e56484a4541565935314b57573330222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\xf0a660ff31d88dac12a465b49a6d0020231671f97de86a52caaf4811603ac301	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2245565935424e53383157533845463046594b42433638465647354d4650523151444a4a57534e584a3036575a4b43523757373759574d504d41424b364a4d464e38484845454e4b333753453557363337354e434433445a59355450314136325235445646323130222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x9e0d75552335a39bc9224b1d2ff872ac95d69361255f11b881192c169efaa989	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a514b31594d4e3035523042304e584e4b414e51463033394743583354384257374d514746504d445153504b54324746345634393147424748534745544d4b345a343954385a375437594d39414e424d3559365a3834515841475a4333423444454b4853453230222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x2e416b0a56a18c0e4c05033e7e3b437475b5b3e472fd20e633a184790329a75b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d46414156474d51514751514538444a4d3042425341594e54434b51305051344451434e30534a544737374657543832443232444a5754414239515250385a50485954565a3734583535364d38505431545a5736474846394d4a4b364b45374758333741383030222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x433942d093b08b1bc3accd1ed78efb2291adf2b7804461d6c50eceaa58a9baf9	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2243305443365a4e315152424d5439463951365a483739473131434851575a314539504636544533583858523132474738354631483152334d4d4451413057513854503954583956323547464233354e564e4346595138465a54434d585148545a54374838503352222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\xed561b2ccbb208bd4f31731f9f197f4fcf5ba2416a692d7bbed897838aa2059b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2232425159365245355051384d4134385953545134573248454a415a4534423937374d544641574a48363242474b30513633364e34384d423147373252374a4550304d595a34533342523156594b52374a41483052505a3744505a4848355441365a4e3245473347222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\xf7bab33f31c959d9364f9ecd866cb2ee8351d54e5b7ce5901265efaff651749c	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2252534e3733484b435143394e42464a394a4848365441355941314252475331303952344d545738415a4d305653534246374a38434333325a414d435150323844305037523659484a3838534d4d503744384a303736503837535035574648463644483846323038222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\xeb9f7928d48304f16e1b59a9b86ab4e1fade8a4d8a24763b1acc532b5d7db530	http://localhost:8081/	3	22000000	0	2000000	0	4000000	0	1000000	\\x5d1b270f60f859d1f255ec45315d909c8186c260d0d714373b755b5901e48d6c	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22595642455138394b4d30373835393956445a5a47435a5a3937305a4d534b315639524731455648485242475a4e304a4646453556474738364858544a37354856425950534d36574658443730543554393633364d3457414d3751303450414b3152545137433347222c22707562223a22424d444a453356305a31435833574a4e5848324b325143474b4a305244474b305433424838445356454e444e4a304634484e5030227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.245.07.23.21-0395MSETD2PK4	\\x65e848d4f12c9303fa51bea8ea84e249403273368dc699716e6136613ece2298	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234352e30372e32332e32312d303339354d5345544432504b34222c2274696d657374616d70223a222f446174652831353637343031383031292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637343838323031292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2232564241524b5133514342353636455942394b5132414a52595330394e5145433854394e4543514330415a393738533645485a47227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224a575a35354d434b4d44425338325a3958574d4b4b474356304e545957343831594d47524847593033503830424459514151315346543936344b523953594b474a34324237444a5030515a3532433639314e5a31505a5133315937574157374b4b474242474d47222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2243514d34484e3748354a394737594a4851544d454e3137323935303334575350485133394a574245433456363246504534414330227d	1567401801000000
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
\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	payto://x-taler-bank/localhost:8082/9	0	1000000	1569820999000000	1788153801000000
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
1	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x0000000000000003	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1567401799000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x9ef381a84aff252646a157d88eded50f708b2c52b7120d5a232a5b628f9ced6d497e6652d986b581188fb014ca857fd5e765a8ccc4eb7e2ce9edcde39accaa4a	\\x8a5aac29a01f36746f2baa61c818aace568f453ccdd4cf13442b4e94b9a1f6e7f151a22e0ac4b112517c553981a39e114551ceb2e4408e75262b31fff2f1b7f0	\\x287369672d76616c200a2028727361200a2020287320233133383935433432453335424445414432343644323031334639363742464633383245394337463142333637433033413641393938393541443233363236393845304239304338313936454130363039413331344541363243354332383539333443343338393546324638313835333033374232424138373239314530303834434637453037364132443945424545423837373537364635464243373937434238354139423346373532334233364233363337453746314432393342313946424335313138313437383633373133413631353743314633374242423835374144304646303934363042303246343443433344393742323743343145423534463923290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x61de4e6934fec080c3f4c6484815adaf14eabfbb03c2504e71306accb210516daa5d218afe8d8bc29dabe9465b560338e9256090c788f8349766b736ab9f5006	1567401801000000	8	5000000
2	\\x7615304a87736904437ed2cca711cd11c34cc5b9bf2060bf254b83097735d0d519b9db909e2c50fc5b231f5756e437a4d6cd40eef7ec4ac4ba38a5e9858af9a3	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233931323535414131353937453343393739333432413633363246423238383243314246304546304436444445463636454442393033353946413535304133333930353938453333304230453045413033463730303737364530454645393543423335313732323043434532414433334531373241464337373633413342323135434537453241334245463333413546433530303230423942464546393932384145354341434239353734443438384233423835343736353034444439423143373939344237313742463832353937424443324145363236314243364333353330394539323530453941353834373241433242453633423935443035324142393923290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x9ed59e0ed340787b2c0f0b4def58dc0cf7cbd5b623c54a3b8115b966282878da3c5a1d119418e52cf01e5770349cf7147f3167058b3486924a0f5bfbfd875607	1567401801000000	0	11000000
3	\\xb2bf3f1a7181e0914570c6affd5db834a3cfdc5b6d793b77414b575f5526bf009480f723c265e2d249a9d35bca07a6488ee8763f4a578675ebe9448f5f4b9337	\\xb825fd04509ad584bd348662c71e0261325ecdbb6a53923f76143af79a2e3ac03777c3123dbdad2613777b4045090f1036449a5cf67783826fd22c5e42fe58a9	\\x287369672d76616c200a2028727361200a2020287320233546434446344343414434363941303230443843354445423842414142374342314445433742324343384236303644353042463837364438424234353139414631394132463736433336433039363537374237324644344646334141384633383839373945383434444536343346443539423830393434314231414131423346314633333734353443424634343043463235464239314131433541414335414241333536383444324230373936413235463841433939413839453741353446333935303337334235434343303835383139433444443338394246363539373843393634383146453842464144384434464231433430353930344144373641444423290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x396a5eae8b82845346d0c36fc1330e594d9eb2b94051924e6412343cacb5d62715a79025fa4ff9c29cf22a351c1909a84409cf5ba230e692677dc32aeb1a5205	1567401801000000	1	2000000
4	\\x90f50699cfe0c0613fb43596c731e53f901048ab93962dc63b681210a2851e6a5be88c98e38205641cadd283a43b1f07e78ffbc81e93c2835152c4b94f04ca36	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233646343632363730413330323545343342383835463532363934304239414542344334453634323846314531363630454435423439313536383043353342313046433236303432313637394532323136413844303041354431444433434245383743434641424145454141453543323734443732313836324137374433433137363341353335423641434445384645303539383130343633384333424545393931434341394445393733454134464233433038453445383634373830313143433733314330383245354135383746453236423346454641444445313436303034444436343841414637454245324643364239433945354342334633454542323723290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\xaf120ace081ab936198fe537564ca34bfd39b8f54aef38a6130854bb2a395b39e334ed16f059b955e05d1af819900d2336bc1b09d2efd7aafbbbd26d55c75600	1567401801000000	0	11000000
5	\\x94bec146d3ba9b3d18eba0332514a508e7e02482d5ab358f911823a725016654d5035e78a20a797592acd5f38db963821ccf0579303da3508ee2b64ddf2a6768	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233737363741304541343634324335344333394642363443304534423132344237313636444245393141363238343736434639463633323738414134463839464342424239463943413032443739443936373042364131444534374341424437323646333139463830424330464142413842464139304539364232434335393336383344444232414246303642424642373632384634384545453535314430434638333433334632414643334335373246434236313146423433433034343439363632383038344144313838413438443032364445394235423042363741323645303936393538333437304143373730344343324643364243314338423235454223290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\xf6373a808ea9e2c47b3acceaf72315ae1147332175affc5c0aef24f1cf02fb752eb5ec3244404834f94ebde62f26170ecc68ad851398f33540b842fb33fc360b	1567401801000000	0	11000000
6	\\xcee132e3166aeedc10090eca7c93bfe76c62b177916144a2dd4396ff347dfe4c2981cb1e72d358bd3492e66a5e1d5a1e050462a576496c26f7bccc4d12385642	\\xeca9b71e64b6b04f1a93e2e4f822f067019bbbe86df30fc42348960939cb109fd89cf006876d778799c04d70e84d6209dc7f23ef0ab855b8ec85fe7c0b545317	\\x287369672d76616c200a2028727361200a2020287320234137384343343735373732313739373437303341454533393244433546303134354243373446393931413532344138343636314237393732374534314431343230354632313943413433423130454232453045453241444542443437334434363546463939443239383831353346303630414237433937324339334139364436313437464245453132333646433333373545393733423838384646373739323045364146383932314644453230363336304545314532324434354142324242373943333538393738464239443833363530443943423537413231433133443330373138393836443844424237453043433841393932413445464438304139304423290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\xa3c062a9c313fe7c0bfb9b7b542239f4baff499e21bfb5760c55588034fe2229645aa79a844b059dc6e49901efe1a828396fc47fff137abfbbcb9e1768572a03	1567401801000000	0	2000000
7	\\x233fb198601bdcd79a608b6d166dbc97cb823ceeebeb7eb1f30cba9d19a58b0db91b3ee303e61306399df78ccf3ea5a57d3b746658301e6ad3b14152679b0433	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233346333543364631393130413530363138353442383634464441344431454435463738463736414234413834363546353830343643333734303143464141383434363132414535344137313946453346463041453230413530344346383630353539323635393742383741384539364541453146464137354635423734384533443035413644314332394231313942344244333431423035303836383534434635363045303631394632423737393336383135303534334446414444304145364431323435383335383636453339333343434230313943383543444542323534333243304246463131393633433445424632324333364138443439443831444123290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\xd3ca13b59aeea844976bc479f9c94f2c7eda8d32ea6905e5a7c47c4a307106209cbb48a33ce90e58478cf29793fd8fbf747a56f956184345e77c7b25798acf0d	1567401801000000	0	11000000
8	\\x05f5592e949b45ee10f05c77376dad03dc83c3d0e019295530b3b2a077ae463e14d5952e2bcef6bd9e560e9ef57d537c6026fef4eacc87848d01bda281b96adc	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233335464344433232333045413833453845334444394437333237333645343037343745313845373545323636374533393842303241344241364538463130324634353033303742384341314336363741343935454146463245314231323338334636363844454136433432334539444333463837303731434634324533374430343636414335453846333344314332364439443733453331444537334332303242353445413538373545363530313043394431374644373932444530443837344445313039303936324134453435353241354139304544463046363138323041433332303239393033453142353130443745373741363745343033433234333423290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\xa6f03939692d22b1e9a7b1118ad02d932f33b6e388405c0cfb3229177febbaecf09b8339efdd1c64bfc52480c40831188a6ccdeb00956669b5d19ee7a0a5540a	1567401801000000	0	11000000
9	\\xfe3808c0aa52d5ee91a32d726d46b76de51607622e7665a23c9fe9abd402968858d74555347f4821690e656c4b529c33c55d9d4bb2bf041c02db28d67822ab35	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233443303146344135323343423034343443364344354344453832323932393132313546424444433846434241364430343142363035413430394532343438393236383632314134364345373645303846423831313832443433324143353931434534373944373734374634463932343832374644313242333432324144424639303142334134343246304139424337324135424336314233414343373043374546373043343333423434443638393937353942354333334532394135453046324533333439313446303343383535363933353345364536304137424233323145333935423734414139363742454544304243333142303334453332393537373123290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x36f6e211ab6c32dd53b1dcfb379fb4793a848645e259a775ca4bd1a303f841653198f942613543d6dc1bf22afad44597cccb5e4c5af3063fcddb7a5582bac205	1567401801000000	0	11000000
10	\\x9d0fecb3020d696a32e19f7454a8e4b673c20a6eabc262dbc0bf1c2a6a4cffde76bc8d53ffde699179f0a5f878cab74b55d0f5bd00f76663b86fa1954956017e	\\xeca9b71e64b6b04f1a93e2e4f822f067019bbbe86df30fc42348960939cb109fd89cf006876d778799c04d70e84d6209dc7f23ef0ab855b8ec85fe7c0b545317	\\x287369672d76616c200a2028727361200a2020287320234131383242324132353241343137333830413434384641413831393442353842323936413535464236444137354136413443353343453332394546453734453731393231383532443145414134433945414246383842464630373830304141433044434243383631343234313930363733433742353343333542443730373936364439343841424131354343344336324234343833434437393936374345443537464233423042353441343035344330333138313144453238373442433236354338383533384141313037323946304243313335463232424636353835323834463942434634374131374443383138334237424245374444453334374442444123290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x1354901a105210c4ba29f6861437e8b80e081021a7cf1772ca77d0a791f21b3d156ed37033ce202aa4e3bf9a7911389ca721a780e46915a54c16907ae263250e	1567401801000000	0	2000000
11	\\x3b0a22e4d3b4c6842c9fbffc429bc1c42e048ccc264682abb8519acb43d49eee97d680e4a8c9c1dc3d4f6d96602d38c046e437a42fad87243ebf990c57830595	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233235353245443246373443453443343642463532384434433832323446383730424236303145323232453042324638363636323037443742413835333841333235304433323231373631423844354246323643434133383737454545324438414543433730383938363932423933423046373530323238313846303932334433393331334532324137413544463234303036434142423236303332353134443546443835433531323741313343393232313646433934324436384131424535413641324437434238374439383233373944333537323945413734423737414431373544364344464436323034383532354435393846373437333741323636463423290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x8a5d44ce36afb986fd97eefad4fba7cec59a5e7cbe01c09bfb1ff2e986ca11fe189b000b3a75be27fabd074bf9834ebd308c9661fe19001fa4ec805fd1512000	1567401801000000	0	11000000
12	\\xfb0bec3465659f3b8211afee282f40f1c7950c8d303d0f21345409e3c9463444403e9d5d549d41d2738c5b2ace598ef661e4714cd56e212f19df7485213b5e2a	\\xfe995ac5bb29e75f6f72b1ef1611151315f7cc53ef83a743447c661c8615a4eaaa72e100b5b5fd210bc632cb02f94be8f6eecb489c276c800725b3a8fb18f85c	\\x287369672d76616c200a2028727361200a2020287320233734354642324544374343313037353632453135344630384341414337383739433441413541393931384238393834433634373539463436364539323543383342464533323735323538394542333034443932394532384643373144353832383532333233343842414539323633334445344230444441363146373739423637303434373143443333343841354237464241323739363838304531374539444342333331454443463246323242303946303730303042353045434245334546323644443737364543344143353737363238363335363244463442394131383544443530304432364545343341464531423441303230423932334333423443413423290a2020290a20290a	\\xea1f28757456c8c7230f07b8ecc00b42ce0041b008417a5dc06facfcc2870727	\\x6cf01996c491232866740ae29b85ca0afeb56ee645a7e0abacf50c160b7e6f3ada41baab91ff5e226bed1cbef732a9f7fa401374f5b7b541adeff36ebed03601	1567401801000000	0	11000000
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

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 10, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 7, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 25, true);


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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 12, true);


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

