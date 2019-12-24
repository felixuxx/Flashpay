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
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea
);


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
    debit boolean NOT NULL,
    account_no integer NOT NULL,
    amount character varying NOT NULL,
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
    withdraw_done boolean NOT NULL,
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
    loss_frac integer NOT NULL
);


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
    payback_loss_val bigint NOT NULL,
    payback_loss_frac integer NOT NULL
);


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
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


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
-- Name: auditor_historic_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_ledger (
    master_pub bytea,
    purpose character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


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
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


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
    first_name character varying(30) NOT NULL,
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
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
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
-- Name: exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    coin_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_contract_terms (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    row_id bigint NOT NULL,
    paid boolean DEFAULT false NOT NULL,
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT merchant_contract_terms_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_contract_terms_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_contract_terms_row_id_seq OWNED BY public.merchant_contract_terms.row_id;


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_orders_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_proofs; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_refunds_rtransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_refunds_rtransaction_id_seq OWNED BY public.merchant_refunds.rtransaction_id;


--
-- Name: merchant_session_info; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_session_info (
    session_id character varying NOT NULL,
    fulfillment_url character varying NOT NULL,
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_session_info_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    tip_id bytea NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: merchant_tip_reserve_credits; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_priv bytea NOT NULL,
    expiration bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tips (
    reserve_priv bytea NOT NULL,
    tip_id bytea NOT NULL,
    exchange_url character varying NOT NULL,
    justification character varying NOT NULL,
    extra bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    left_val bigint NOT NULL,
    left_frac integer NOT NULL,
    CONSTRAINT merchant_tips_reserve_priv_check CHECK ((length(reserve_priv) = 32)),
    CONSTRAINT merchant_tips_tip_id_check CHECK ((length(tip_id) = 64))
);


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    wtid bytea NOT NULL,
    CONSTRAINT merchant_transfers_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: payback; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_payback_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_payback_uuid_seq OWNED BY public.payback.payback_uuid;


--
-- Name: payback_refresh; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_refresh_payback_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_refresh_payback_refresh_uuid_seq OWNED BY public.payback_refresh.payback_refresh_uuid;


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    type text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);


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
    newcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


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
    wire_reference bytea NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
);


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
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bytea,
    wire_out_off bytea
);


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
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
-- Name: merchant_contract_terms row_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms ALTER COLUMN row_id SET DEFAULT nextval('public.merchant_contract_terms_row_id_seq'::regclass);


--
-- Name: merchant_refunds rtransaction_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN rtransaction_id SET DEFAULT nextval('public.merchant_refunds_rtransaction_id_seq'::regclass);


--
-- Name: payback payback_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback ALTER COLUMN payback_uuid SET DEFAULT nextval('public.payback_payback_uuid_seq'::regclass);


--
-- Name: payback_refresh payback_refresh_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh ALTER COLUMN payback_refresh_uuid SET DEFAULT nextval('public.payback_refresh_payback_refresh_uuid_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


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
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: aggregation_tracking; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: app_bankaccount; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_bankaccount (is_public, debit, account_no, amount, user_id) FROM stdin;
t	f	3	TESTKUDOS:0.00	3
t	f	4	TESTKUDOS:0.00	4
t	f	5	TESTKUDOS:0.00	5
t	f	6	TESTKUDOS:0.00	6
t	f	7	TESTKUDOS:0.00	7
t	f	8	TESTKUDOS:0.00	8
t	t	1	TESTKUDOS:100.00	1
f	f	9	TESTKUDOS:90.00	9
t	f	2	TESTKUDOS:10.00	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100.00	Joining bonus	2019-12-24 19:53:01.313857+01	f	9	1
2	TESTKUDOS:10.00	Z5DRGFNJXD7RVPGAJS7XK7BWNFYTDCX52G7KXQQHH977S9Y927EG	2019-12-24 19:53:01.40651+01	f	2	9
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, withdraw_done, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x158f062de0baccffbb945f80194acf9de09307f343a43f028d752d15e9ef7c067c0ce2cc6ab34b36fdd9de7a6be3dcfcde8819fc162fcf0757347d4b258f274b	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x75c65718532ffa4675639487b6679ed939cc368da632809e7559687969cc4c7b1ac9b8c72fa07766ab0015ce83e6124367e6989f883226312f04fe53dc586b7d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22a315624aa89b9367f026281575830dd8ed12fa466f194c0088b8efc8a35ce8eea3c46462ae6c79ddbd8164f21076047e5ec60340a7f035d744e01f67bc7a8a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xebfdc3eecba5c5cc6dc7b02f56805ae68e3e3323b5156bd32a2e137e31afe2d147540119b9e24d83fb03e1eb20fe02b6dc8e311e5a18ea18c008febd2b9fc565	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab474598aac8d361f68d596cd1cc3bcb2a69d57d93b6bf691f96fad54d5dc931f6aff0be07501a7905802c002316c32bf333fc2badfe6b14a0fe26a566870f57	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x21494da648f815c8400f3f501fee5094d5a1c7200385c34d0068a5b65eebde4a2c1f052ac4459e63e65afc1d70874cc27978ce39aac96b1019302347943d81ec	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9d002bfe81ccf9caf3658ec01a93c4c65fb6577e28ca256a11743d9a11eedbcfa130241010abf5a08c6280394cdfd650b9507c94f32bde6f730c3f0acab06c4	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7602453a3c5b5b034e4e8962d736e1c285023a370d2261bb8e6c6a0bd25c6874b6bc2b270b2e3d53047b0fd1d61bd634038de340056bca1f8fe37fbeb03e12d4	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76a1dca208d0ccfbf255a65daf971519fca9ceb8fba07ffb483e04cb770212f6b87c78f93d2bab1c5c32c626d84751e22f6505cece5b1e00256998f5e7509477	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ce541fa28ace827cbafb8c96e687b585614a7de08f2b19e88074a3868709583ac2226f5d864e2ab3b7ab8e834f4a62646d4b0f4c2ac758f8863cd87d6ca195d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9cbe27574c97f1c1251039b06ee28d0fdd78fd028e0f076e17f61613d47ce8a936806c7b2b63ce5e289da818435b18a37080e10d72751a39fc4406ce1cc2af7b	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9f39a521537dd6c8c55b838a1ef25b608634279633b86d1f8f4cfbd9482ec266296a58f4bbe864123e72aa7c5f5d7640df927962b914a8ad3dcc606c2550354	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6c0c8978e5ef84659c01c2d1d81b622b9eb429cc12029172e52a94c200f54233017689a7d703ceb01bf15ec09e69ea5a55aa82ddc7849b2ca99fa4756ec6dff	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f7d2ec588d4623376e2172ca156806ba2df0b0a1089c19b87422eca48a9d450bc4cfdd5adf98468e7a32f8eb363b775662ac017b6e07c063faf4b25a687c0e3	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd85779530a14991c38d07470eb6988d46bc98e52db6c3be5de3cbb982ee80602bedf06aa5dba249a72560b1e494d1d9aa88d6190a9d10bbae478b317c5a5df07	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1db904aed9951fb44b3366a826ce71dcae1c57bb751f9c79eddb3304d212c53b0589597a899f8720c7925a6459707ab932fb3e1258694c23571ab76210b924a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x052216456730bed5d5d7f3b0e17f06d3b45ca38dc69ebbfb8a72d517a0ef5c82af81aaa622211604dc81d6d56fc56570050890006dbd5a667eabffa116981b2a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4b54b2c0b3828c4d74ecaf608af2e7b7ca5abb98fd707cf7d77371f687ec1b003bde51eeee4c68661f011c805e689472aac733ff0601561b303647b811287b1	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79362bb718601436f3b4d3bb533610b8aaf663282594ef828a985fdb9dbe0b6e3b0d79abfe606de2995149d10166a957350428edd876b4bdbc018e519c76d81a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba3405b03f4f3ff8f0e371d324bcfd421fccf9a580648b69f85fc9d7f58d5c40bfc31c40a19b33ac034b3c41a3e2e7aaeb9deaa0aba214d31c2cd2c16c6fd531	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d7d11ea0e04517da9ef70102d5c51ae733b5a5b3e2214074cf03c50b272596a6b89bec3a6aa5aab2733322356396853fa7d6bb54dd07f8922351ae0fb4c855a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb57ceaa3636b5169e48e2f3493f301459d77c75e529f64300a9a69206acba26d61b16e700f00f5e2250e9c07ab3dda2bdb5a53e440fa8d0d5291e1cddfe30e2	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9032fe5aea5aafb444c1edb54d9125f9b3b8848489ee5db6355d968bac6e8e8d9d25f39c58db24865d6dacae4e96ea03427c9cd115870f1c55776704458d40a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a1aaa3ba7bcec20d46d4689ce2df9aa88d6a4cbbf450e09d902e1fa93e6c923bd767360d4ce81765ace97ae2aebc274314acd1268ad7835ed9b90039905e244	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x27cdeca0a6659d152a3c78254fe090f93fc0c381f750514b9af6b66847e7ef888ba34cd90fc61228ada46e835abcd78f9975548adaf4ffd18bfb4303d9173637	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e5357c04182b7d2c72f2dc640fb7822a7ebc62aacd54250fc112aff2421fb2863650df1c68d16676cfb166665b4eff23398f27babbdb5e5b6576f74611c9347	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4126b27870f04f57e39952c9c741fb3094087b969582a79725d0bb76afe26ff1e856b3930291cfd2fd594157068629b5ebd6101d7c72cf52f84ca2b6f9aee9e2	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb228aae4fd8474b79da2f4e2e5d7f84226fedb723bf24591ed0526da98b37165b9e9b69210152407e50463ceef777e160ac0e82d5c1f39760590d198574f306e	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1fe873c080ae7eb627cda23618a457e05347fe666915e706e6a1cb23177a1835c645c4c636bc9db165f8639469110ab4920407e253c2ac9e470bedbc9997cb3d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf0365353b2aa21bc4a79b0bea642a797cf856f65ba05f4e641b1ace1bf42c5ec3361b12296b9786fee41e5bc55fe1c2f9a3bdb6d4036a3661de6bf9610649880	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbbfa87ab83c074820cca9ebfeaabd4e01a13f5cfcd9e5ba3aaf885b42db470c7e9f5ec6558e738b96c63cd9c4b9a4498de27f520bbe1f813b5ad988f42672eb0	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55cf0bdd3e9ea55a500d46d64bd1bb68f73935dfdf382cc8aa7053d9a2e20789c7f068f758a10faa2fe839157f934ab5bcb90fae9476399ba34c30785f59c34a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e8c731ffdd4ec42021d1b15933b2a785b99f9a9a202168c84d4b5754c7a5582742616370e04a178d3970d28a96e6774df93ad4f6b876b0d648d16421d20c9f0	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf4cd487b491cf026772fc54df30424f552dd5c2966677c35fca940791d8b9385e4bc3ee676c969b57b85963b0d84618e605fd26fc1bb0683cc4066004213122	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3f116e6d55d4ad6f34475c167dd7b7028ad5117682986843de3b3af834fec1a052518c8bb07483dbab3de6a9570375ce96603b1ac467541292e53c5235f1283d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6691bcb806b51cee0a45b9b0a4289248164c0721a5eba43b65554b860bd7fb75b98e49be3126cc4b46b07bb8b79b1f442d616730e49d8cca877ab2d58e1cad88	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xae99b3efff030938edf2a4c298b04dd7ccca38e4f6fa0c2f4b1602d0d15c0daec6e376458a45874953affa19142616fa2d75f0de8ce25a55a598ed076f5f0340	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9889d9d3a8ed0aaed8c2e2970acb9a8e26a361a3866fe842d9f2044bae4a66df10df952be4aaad24e70748eb69387e7028aaefbe41a10328a6d003c4cd5d7660	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbd9f65bf3c233f447068a91711ca388cc597a7fc3eb54c242af069d8344049a85512f5dc833b13180ddbedf24a0d2506df0f47c20614c5eba7801d4d7d231f36	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x230f523f6e4701174035d14a3086fd9e13eb0f8340dfd29a3cb9fad261553dd46748acc586226a81b17bfdd7c8cc38d613d669b5e1c0a5dbd3596488be8bca9d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x21e21b6aacfc5a6eeb7f921e76683245d4380ebe44dc2e002e7f91c892d8a1740559bb23c1a701efbed3f7734e337a1213113da63edb1f535323dc0e23c01950	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x626bfa9920faa53f0c10ad74ce7ac45bd3185631c2f4cf7d398e2672b6752cc3ff51358bbbc6173b75d1b84a64eaf46a8a40274243a1e7bae80514f30ec2b275	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x17b7b4dff88bf818027b50e3bab0c3537e5ec5ae89953568d42a799c48d10aa738bb754df1c400585cc92098bf0fcbdfea8f1e3b874a091135d5f4051066972a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x60e36c7954c6dbad7fb31bdb2480001d472cafdb4541a5ef3edf4f86613f2a5d39fe112b48f4fde47297033210614998b5b421a6b69c69f1d2990221d7ce0255	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x667306cc584dcfe92c8fd193eda007c4f36a0564fe9d9997b934531577b0ab402df801b39c5223f439297278796180a66ea3d28097be71a0ccd9b9723db61b92	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1d324d66d3a94f6ce3030aaf31eb574e26805f9b434460bd6914d335f5caed27cd52c04b8a9c4f633556dd2138d2ebe2885349f992b0b02d5e16f32c12ef69a7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd8426510419d670ba210317c5fcd8030158510d17f5299d446d63a7f926ccfb0d3a6baf33b6ea761a2d448e2b0a18654cc66587db42822edd2ce4cf99449d352	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x973597cc20be0a81c0f8a19512e16a59666b0b55ceef499949e6ec068bec1dac5b4090182aae75f088f3ea3fe516de6032c8b9681362ebd09d4576a42b8cdf21	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x01a2cd22e2e49da0ddf0e5b0a2756af06d9792005c19984a76c6efc0ef05ed7627f597d9e1c2d1015e9b06c3782a673d55b2a469726fcf737655cc4a8e307971	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf2a1cf4d7e769d392c3773defbab09419b348679624e0857b14e67460a681ef2bb84c883ea868fa674989f08331aff091a853655059c9e831ca711be9e20d503	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1051f247ba7b6e0ecb5e43f3b52a3db5c247ed1310b9150fa5b323e79b06f5215c6bd3d218789168a2c0a38d868f3cfa0fb8aa13728ccca3888c36282d034a54	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x464dc26cfa783dce899c10ecfc7531a03c372f9d4df9967be0e7842d3b5150bad6e8434696a799218b3130d500a918e99bf9c673fa2d593568faae0a819eea41	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9acb16772fe33f5b839a55d51fd54f8bc6fe7befd1f1a7a2b2e35d846164ce8a7edee40ee3b249e1dbf5b19c520f4fe5512c1a6e6b1cb7bfdad754a9dd6fc002	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8b977ddb87ecfcf340356aaf10b27eb4670ddf7c665f2e13ca3667b2557e3134221cc5bc585efe4bb2184fceb68bc8de2f76fc46c66214b51e30675a277cf2a0	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe2b479f79f9e7526d2b59b5c3f347abd7aeb4ff850fb709545e0a3c21010ab07b53e49d7853c6903fa4434528fc9fb8e36c00d4c30443491dc74e01d0c249ce7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbd39a311aec3b350645534fb6fef8ec7e06ba38540fa6d338cb5a8bce7468be65aad49ee1f22443df97b1fd42dbed043ca4f3ca13665ec60518a42ff8a4a91cf	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0957731517b0c150fbd9a361fb9a8b67c33b8e0dc2d2a7b8447db7e52ab9a84acf5f1c79db6ff80ac565ebe0d4d3393728be0a62a3014e83fd1b0de936d08b79	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfe1dca533c388dc5396368a8e0ac4cc9cc4c720daa9ddaed917024574789d6d274d3e106859f0a9e36a6b92115134dbb54892e4f12730441ff3ad307d4c5f577	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x040f2a0fe8b5c78c1123f1e3296e5ee84b25e7cd7beaada4e525210910dcd876d2f3428cd0dab46b86cc10add586227ecfe701bd9460c39da7e08285b135fcc7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1b117dd42cc30a0d07ef0b6c343f8fd7bc58870ac57accb790a5bca5c267c8935e4a5ebca54986f7a37bcf6ead9bfb0abb2128bb4d5c77c913682cbe3c1a8a00	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc71a370beb41f468ff7ed459166a72f4cf22987b679d1a284defad7b2ee26f8bc9221c7860ded1c31dc472192a08a9ea7d8d70934e9b990f7e675b7c963714bf	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf36a7f5387e1917bf58ba05e60825ef1b50867ea991882ff0551e54b7674f5a94c063b9d2fdaf41ebef3daf97c3c6a680f95089c345bf4385c6a480f03119d31	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x36fa953adfe31d931f4dc6629a73163d1bf1e60ccbf98198c0e2a68c69da380d976fc5e1ee477c67ab78bfd8148a3e47f39f8ea5a5feacfbbd9492310931c0eb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa0bea8ded03b6a920cb85746f0221923522cddb50534410af591e92bbe8bbad29b024096082ad6575ef2c5e5a6b65c809d6f15a2c4f6a341d67e21b886bb6e6d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x150ff1149621d4a8bd9b989803f9f47e912195c8a3360db7d0769b81065d3ac8f26b1149643dc529b4b584c149235a51e35ea9366601e69bbd4cd579a75169f1	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9ca86484eb30579807e3ffeead00330c32973120244d4b28cb2f9a32e315c88a3f756eec1547d15a6ab7c4e710f4c8af3baac6655ace96dad88dd464df4be5dc	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x84391feabca3ff5ae3957f42f599650d4ca811f1abe095d0d1b6133fbe47522f440c5eaecf75be31e25a4aa114b145c198e109113fd60331778069b294d0d4b4	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0883b7e676476ab4ade5590ee39b22ae6690096c5fe862100d5cf92cb22ec6b83da6cf619832d85ba774d7ea8a2123da0fab13c497f59851099ef1f752ed94dc	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39bdad342b1831e6195c2652e40e3dbe1e932bda7b08382df1a2a5aafddffaaadef706ba399bd76a442faf1757a30e1dd1e3cc0d955f04bfc870e71be6d1a034	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf666a6e694a1050c6937075cf2e8d32c0b07ef07ca7cf430dbcc8dd9abdd46738734faaf2c9bb2b123b2064b20118807af648974d40ad124d34c65735f38f30b	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8aafb3aeba3efca982678b08361a7db49dd0a3c08f8e2608e5a6a7e7ac365b47c6fe90f9f0d53a8c94a2be49aa9a9179d441ed1c5e1dfeff1d59cb5d5b97de26	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6676ebb256ea11d69bf6093031bf5578dc605c83f866e4b08e9b16c4ae76493e438953bb509b132df0c19c00d9bf6d5611072361b04d30062dd25ab52665c39	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f9853b2e82aef14ef097356822f41c6c0df5d4682652668a1bdc08aaf91f9f343ec0ce51da95a23153e3716901968c987f62e51f527f0ff5d50a1e3e8e18afc	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e2414347dee94061e21d5c9746d782d18760c3261da742f020b34ba7dfd1565e2e7d49fe0a4f45205c2d321c208d652f266b889639fc574e68d0e5e9be0b0a0	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x21e3c83462625114bd4f29a020f983c33e4bf09a674c86fb544a88b320a07178215ad09436da1c97af1937c7dd6d88195721ce42719bf06b42dcb94a21506fc1	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c0d36adfb59dbd47d795b4d77fec7f68e67c28088c358cbc5f19849e7cd652c360569eee445401fa868671998ddf14f8144666ca0d774db905448776f08caa6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7c1d6320524eb36b783c275faf1478c95d0ba1bbfa87635372ac2b4b66ab2edee21af371b2b9b42dedd9ef856fbd800978ce70af4f1fd6e66670cb9df55583f	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x579f82bf0629a64a70fc51bef0e76e599b6c8ee74cec9e54b4c4945681216b197042eb3ad14a1b0dd78eba6dd7991b49d08df39e43f8ee3af2b0e04c42878dcc	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca3255ec2af75f463fb434ad3a75db4d1a002c8cd42fe6a0b14c9b5d40ac32266587755e7fed0ac582ccc59575de3130979bf07ed5c38ea9f31f755d0e39baea	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdbaf2d5f2cec51e0e87b8ae0e5cc0f9ecfc2803767a1e5a620a43683f4a380ba5db74a0fffb5cee673cf5b4fb5a02ff8955913ef2815bb4d44baa1b9c22e19da	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a475a80a19099153483503fa4993227c93266b19204847095d4edad60d85d06c12100226eb7623583e83f77a0a8e6799c961233e5ae1c0360558cae13cd0457	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf7ae7a39d8deaf2bc7e642f5c19faeaa5ca60d1d440033743ec87d2b6d2fcd0f7a56ad46ef86ca32f7cbb7aed0ec93c6f7eff2f45d48de8e5687f011368bec51	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf21fb85371842a1b6d154976526bb56ba9c81ce5d899aca461ece433dafdb651836ca4a6a630b986094086f04213e0ad8c50ac31913fdfd8a09f4badef8961e	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79b073e9c640b9166686ccec2cfb2122b24189b3f581e863eb068d66a6a7b67cfdf49df7e6ab443ffd2e94bea0dab9c26d9c04f1d056e2b1581769f5ed954536	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x021988916c8b3d5265903d73f9071022e74cb7f68c9c295ee7b18ae00bd0da1afbeef6db34516f2f64c75727ebb5d3ba564f13f5b8c595637b9dabfa17e876eb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bbe42553fee05826f33e844a72573202f69245d360e39120399a29c08dcafe58ca64a4f9cc380b68073fe54610c320ed3bd1ac0c0b94b2573c014301de0f4bb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8dcc67ab7f241e25b3a911b9fa64f71cb42beb23157ceb3c731530bf0014c169a78a457582095c28f31b02b98e754b4f7a54dfcd62276b008b344745a6bdd83d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a1e49e1f4e4b3ba71ef35b899889151ecdcbf1212c64e37466be66bc698caaef9cee4e6dda254bebe9486116e38a8473935e4f20edb9f5b7ddadbeb8e83f2c9	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b5401d8fda5d68b0c0db5bccb2bd9a1331717fe91d32960ec12c1e43f7d68792f0046e8989d4db58f6654be097c7e9e99f63f498baa522ae04d92d0afbcf631	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x341ae2a4a42308282dfc94f2be5d964091d06751580fb6654920bd53c12a8e60d1f384c6fe2c89b91882c19287d31b1c1feeb286e49549d3f060fe660575921d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x47354ba1b973c49d61c2c79b46f6518fcdaa4fe0dfdcdd37eb46cdf2677073e031e50f21064cab6765def9b6560de18c2024480cdf107816ccd4c7a3197b7c84	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1a73eea781cd16d20d295a99dc4820322f172933b745cebb648776fc53c0ea0396372873bf237cc45666c8e7ccd2cbdb6e3536dfe29f9f4691291ca43a8ff23	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0ca81c09ff4279286bd05cc3047138460fd37aefc0298d93758e0396c3889067e7ca4160c85b9b2680ece1ac8e97586d3e2ea10d78c7a250a041e3431217d93	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d3fa00c98175af5a65b47e04814c39a66e10c0bef21420e170dce6acc5199da6ef96b2da7f93bc72c5f3440fb9ddf1d2d90ec0e65bbc0eeebd1eb3cedbae809	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70651eccdc53ccc2643a62d5ac16d1c89c1ec3672744d8bd7c99b52f6b6fe23bbcf4958f8687a05088f4f022f67b3b0654c6eb07572c39d5b0d003c1d4257ff3	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdd13f811e79337ffa215847fb08f57e4fe94662666e6f020158fed3eb0550d30b68ca1e6bd48fe904650426b570803c11983e60a16a2ccc5fb64937e975f85e3	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48502b16e759fe59ebfe2ac746bf3ace41e93be7dd274accb0e58960d5af1d1f07c625fb54d58777397e99370ed67fb30285b0dedf4d539aeb1a07ea328114d9	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9ffe68b1db08494538b4d0fd9c72448c68dc7cb8367bb41291ecaa95245934cdf93ce3636ead9468eaee7c8cc406cd9d6784ab40140b09347f78420acc0aa6be	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a60429734516556928da00daae0986212feb0183025624f5ecc38256a50d663452e736b88d29353b9439de6e8210dc75308f14d7b1af70bdc669f77a70392ec	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd47cfc07933afe0536e9537b81c3f0238ce5e7e88b5c57b1db2924679e56b61a9a9ccf86a71e72af5275bbfeadd463a3982e87771f49ecef13c6ab78915eb607	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23be0b7b4f0a2ee8a807f4d3beb2e44578ccd9d48bf449976f73bd4c9c3e350406401187f55fdddabb8f84213636ecd4bba441b576d779b22cef04829026b3df	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x537b4c186a601792d0a671aaef2443bac978002327f084a533c69dddedf05436990f7611f894f6218e41f4bb06f1c231873a80e74a60ac43881e54897fa658b6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc023d2381915fb1bee2573f43e0eae6e1cb8af166c6e76074713d4947b70883deaf683f1e07e60edc113de600353cd4970df8644cad56f4333bfa8d33a07efe	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x564e1a55abaa059f4ad7c5b0127412a65f06495ad56313e432f3b833b3e9d84046a74b1a2017adf46e06511c40becea20f7c45c9305eb606640761b304164bcb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c70d026cdd9418addd7654ee2d345448e1e6f0c3510fe9881a76d717613c33e56a21bff61afa1749a5c197efd8708175516092a16dd0bd61c0934959fbb2797	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe9838fac09605e4ad4cd15bc4e0acad53cb50bc7ce2e428cb734acc1676963b21d1a0229a2e692a09217c42ee6583cd09a747907d9d4ffdad3997954d12050da	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x57050d11e4e9fc9e93ed3fa81aa31a6d7294e0f8aa8bf7357b1e431afd6a88a1df227286ee8634083c370eee55bb8bef40d1db3b394c7d466dc136440e8c70ae	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7d5398864cdf9f5b78989e780458afe4ecf9d5a592b0195a0404dd3acee5388028d5a06881eb72789ceeb6329a0753045d3d2a9444778e3db52e0aca4f2bc3b7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3fd0fa055303c1ea6adbc40c5c9ea3d2c8eb039400acb201b01d3fb0684eb612f9407fad9c03eb65271508bd7dce3c1c39d367ad661c0b6f38f569b6a6d2ab1	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xba55b0b5fb5478e5669f15a84522bb3fd716a5c69a66ced1494029aad53133c22a1677c692c11fe16cbdd7956b7869442ce5775b85180d01588bb38419af23bf	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x44a397af8e416315b44f2b63ba52d3a3565fc14b869c5b7346da31fcc7cbd3135aaeb751a96c2b0671b3b241925b91a69e08a7b9d3de692301ec2a18f5e85497	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x205854717e6d05162df6124daf2246a070348b97ea9240c0d9d337a4626933086e031f383e74c1e1a256393fd6af9b757d86b78d987753a7491244414451c090	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x565b687ac23017416f8e6c63517b0e3ef0fd95593fe57ecaf2e610746664c35881628f18fda810bf7b4ed31de5e980f8ee03dac83e42bf1535ce5819bafe7eaa	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x630e9b05c8fc2f98204d545f1d1e8f64cc1ae24c0106e6432554691a8e334f7e282a798b1a760afa5d909d3fea6b148dd76ebfd7bb24a44e7de52194aa2a484f	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5137ffa536155b3648816ab19b44af9ba2be579da7aa3390857d95dc6d2b6357d4d601cdfcb689cac05793374e666526012e6cb54acbb8c1614f2d9e3513faa5	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc3220852015e484d47ef681420d271032c29d486cfcd7d1b7d2280606099ac1e22cae6f12d825044f6a9fa193fb819d2ccbbe00e85051815e5a7c19b698cde66	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f51288901c4191368c600a4f8e95da8e97b3b89d538d473b73845541ad4ae05f847b13ba2715963d6decf47779d98630d3e4cd8fa7583c4656daa16e5a00068	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf7154de9681e77911636d1591b6abd305fff658ddb58f547418d2a76ada6ab4879372b46be3302f731369d06a751182ec0ef3a8c44d49318d5e38d29d8005276	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeea1577543064da6d4218588fb533eb675e0f6be398ebe1e46c27c58b03f7b048ca31a2b46cb92c75a5d27cb5a3bc311b234b40edcc8a43bfb7b1250b649a19d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x06d68387524146c50a4243cc69fcb4e0b86b0a59814fd0e3ccf13644a2adc4848ed7c93e6feec3da9670b479cbd5d2a8618d82e402bc54a0e94b09138f213244	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2fa4d97fee0afd2a28bf3ee52537215027af09bdc5098876016d53efce7d1ad242d0ccd58ac34f0b9770b334121ffeb8e30c7fb2ebd2bc03e97031191fc1e3d4	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e538eef8f779d3a5619c2fcc2a739eb3121c3a81b6443ce86d7e3dcfde55923ac04783711e06bf0e394034ed64a217273ed8fd8397ecf25841f43aecd03d9b7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe1070882e8321f940be0ac3d73222c88af5512f4cb3c849e02d345369181b1f913b2a5f6be0b1bc0ea2a8fe7090430ee139e44202e6ef8d220552bd6afb216ed	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4201084be8d720ca35f4cf149ea473afb556dfe5af846c80d64a10ef586bb4b6f9252479d033c6c89c106c4ce6a1da300b3c76b317af48b84086e04f61922ae5	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcf7b86321b8446eec6abe9301764d955e34603bd8789b2f51f16ee9d46e9f3b33194c582d89bb4f00998b1bcc603799297998cf8acb102bfd2fd633d6e166b4f	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f537ac674ccb63fdf2c113c3356c64461f79506dc04a6ec90fb144915a228697f2cc9fe71b82d691c8be7b13d261869b6eec43ab92e5bd29aa5c279924060f6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6164719c0326fdf5f811b604e653d6fee2f31c059e0cfff516eed111081bca74977dd6eded456163fc2681d4d89e3f05094974de78ce9f4c4c6826f418d13f73	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9fc9572d0d43acc079b0ded087de82df376b471513f82ec505090f84017ceba5ea7ecab06fea0cd582798c7cfd39bd67edfcf82c272d9d35927e8e9ae873a86d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x89a97bd9bb99f902938db07f8f79a00fcd46307789a43d472245e1b0ff5d38a9ff8823addd78e331cd78c0c03137f6a1ce8dc94b3e38b7fcba44c1d9f2ced278	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5855b3691c7ec39adb559bbc1c843fcf406614b43b00f0714ef9ef4455e457e81142691b7470222482ec64fc1c4323d13e8a23ba1758dc3fbe1ced36f72f3d39	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x02751fe2fa5d52da27dccde81902a54c29270f12d8825dacc9d0c802e0a099f9e28f1d2d04e10a11360a754b4a4e0ed15ca448eb3fc583036dfe03fdc2270b2f	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x327a76f838d8a13b46d7dfe05bdcc0674625e359c2055fe2eb2fd8f4182ad1d771fbd245344a5117331c1333f0d509d4cc7f6c469f61d99183989711c12de92a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xede669dfa22144c16fc370fb9b3230567d597491f7f2c6d3e789967943f7f967196181b9c2c905f53340b6c04d464b1a7294c88c445ae494769ed8a42844a847	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d110dfd54734b5816afa924365ad9a586ca4c17352f0cde9bbc4f0fa592239466c799194e2d057a51eb38e4731fa8ff332644c0f511becbc469532621952059	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd5ab082d4933c4531762845791e87f1eb56454842ed2716fd68722346b2ca0d7e2ab1727af6571ea61f46b05e058261eeec2d7d69cad11df8580b9a91b2d95e6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a2d483a97cc668f9da157246f0821194b654332d53cf42a5c2797b669ecb97972959e930810609294164dc2e17ac5488b8ec59a091c7b63c9a54602ee33a556	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x694864a41aea2372d2f96866690bc8ea4001cb176fb7f87b3e345304ac461fac9ef0d091082bc80a636b04106a1e3e39bc14de24f7abe651149b0f73eac45ba3	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3845fe8a8aa4f427756f802207da4fcbdc4ed0983d52cee40fed37ca7bab5f811958582f46ddf834ad054e4dfe6ecebcbf1f4b1530428f439cc27b9ad53d627f	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x26003c7550e76278c0fa5ca820ac17992b0ec37c071b973211a3751eb7aec7faccbbe110b90580e6a752edb2a8019f895d5b119e3bc2bbe45eeec7b09daa4894	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd32fc0705babc7197bf033ae04d596536474d04500f9180aed4c684f7e03092baaf340c4263055949f1abd345b41fdc4a9fe37f9275e93ebebc0007fa76977cc	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x62fb781f019f46965cee1d9f0a9ccb61e0abe15f32352373d170790cc65dcabf3fcf9583cda38a014373d3ffeaad3b0e882b46051aa8814a03d01ca23585761a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3613cd356c6c3eeff260338981c95fc99093e89bd68493f520170b1b0b3e1799baee654f49a4f4921c18575849b5fcddf34f339e53be49986e2ebd87e31c8c9	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbfb972dc65e32d0a1078980a5e0be349b60bc06b5e83fc0ee297eb50112d8902a6e00f1ac94354bb9c4c339d07a188de9e60c456a8cc5816a2037668f196e875	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdcb1bda7c663dd18134175d0643118d8ef472bafa4a6d3f5e9bd508eed414b0079ee2bc4c013e14220aaddea009b8fea65733e355228cd828c51b8cdd2c63ffc	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4e832bdd4b0303e82be6e958d1cc8bf873737a8dc1c3c2c3c92e06c036cf8d13f2f84c0d101d087947a93341e5db732e5a67842b220b1333de844a8201724140	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8a5fba5432939e993adffacafe6db090a01fa4e06699577894157ddbd042d0d1666dc05d7a0389629b0b5e3551441ef0e1253973741460b1bc3822f606c046d6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f879af494199acf06de395dea9b780d6ea30d523d37c2f39b7b1140ded485ac6265bbc2e1af7af5f5754889a2de2a38fb866537df6b8c6da5e00f415bec5954	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x345bd42f15d8f11f181d835f02327532fbb45416df35e235fab5df5d6c206181653e6374cd6da354fe07a0f50bd1102f3509670cffa4319f166d4cfb1953ff96	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd9a853ffbfe99c24a62372bb87e420224fcdd52901a46ec1aebdbea056aca184f0144f0826fad5daa29c2984d81c1c25b287221f00981ede729118f3af5db715	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x472c753f6fb95c3f1bf61c339cb7fcc548382534e61c04a7c2ef949229e330cb69cc9ccffee690d482657c1ee5c8e87966e2086869e50c9be9f4b56622455877	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xefbeb4a17e96ef0c6e674e5eddf486342b5a114566caef5941f48cbca73f24a7bb3d8bb3d24ca4158b2e5f1ced60e36c5b346d8fc319ef13e5a424e3832c92af	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2495c3c1df5004107715769801be30c8d6fbe18362dbd90156a47024106e76fca9ae76b766e949afbf47ac589ca6f7f5ad90cf946acfc25526b0cd7b6083bebd	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x483fe2ab5bba1cb51d90523e990589bac99a7841469871b0ffd9ea3cd8727c3bb8d182378422925045d46141d108f0fd3489890cfb63e1e04be68de8e66ff796	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x52ce30fb5b0eef9976e50994ded10767df8ce08e7690be71bc0462fcf81f6a2fbe117056f3d5d8be23822c177248d125bc8ca6b0dd7a3ac598c3d66d887c0bed	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x71f8ff22356d2cca1383b411c7a315dec86c307bad74dea4013728f7a8e53fd8ba69b8acf461a8774ab56ab8497d5203ab13c2d3769cc7527bad77f940e911e1	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x001abb651c741983ef71c1298a66a56e8c55b7b0d88a9034aa113627af2d3a5d3c81f05f0a6c781b6cf4125aa93d0df6a537592776234e80d97b2fca0bf36d9c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x884a3e2e759811037e2a1fe3d3550c86ee6a64acc8c2f5f853ad44b3932b7e9954dbd3feb6a9ee9f764660db518d19b53a30ea4494901f92a7662927f97a08c8	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf4b439699b60cf423284e205f6a2ff7d248b8cc77f8fbc3112ff3f42f402e350b6334689e8a5992836d2332d311683790b258c2f76c46d944c1cca7b368a4285	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x986b252ba63624a89fc8427d0a12b7696234fef5b396f4dfda55357c9180dc05a72ff1c0b07ec7434f0e0125a45f525d3d5bad1de78a068d08a3f1fe89095014	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d98de90b4631c4db5f49f31cde0cb3065741aabe319e529d69b02d064f7bab2461a7a6d4ae3b6d20b171f00b5394a3e5141f3ae48e93d4df40a37a7ac0cc193	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbf27b219bb61c224806b716dab35bca0a3cf147948f0ed1473c98509a63a9edc10b4392e5b762b07ca931341f10ebb1182ac2b6618507f411383670996f67a14	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe844236569acdaadd2afebb8e792c99c56dfe6744b8cedaf40ab3af3f85a8c05f1232b08a015fc416d6fef1cd4b87ef63888a3bcbcc73bcf20df3eaa2b9dc7a7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc22b1eb56737c54d8d8b3fd2c85331ebf768fefe646c8a325c23222dc063d286bef707915aedae39a5c655668ba4bf78e60e11abc73992fb925ce876148938ed	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x96e5114ddbe4810600ac58e8a45212dabcddfac36a7256df85ae74d4ce1d16ebdb3fd29b9528c6e3864551679376850cc35fba9498bf237b2e39f26ca0b1c4a3	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2633c25f3b64242e269795158b514f968a0cf434b0b443595a461f43c266372c53ac372054a59ec123e64ed190396bd96f8dda9c0d71b18d2c8f597dc42a6a4	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb31d4c665d78d512f1da0b98da0ef511dea23c9399ab2e30fe57ac47f37703f61958f212a52cc8496cc8002baaca763f5e4aa5e8ce5c6d8818da787aea15904c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xefd6e343b22f86d6d90211ac2995434c918c2ee00989dea97835fd953171307558e2c4fee149e188fad3293f8bc745086b3dd70b62891fb0d23bb196c48ca15c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7c2b54d9d4f8d84146b7b8150c5283720d6d3ea53371499e7858520d12655a6d66344ea65b2866011fb1664c34f0774fb54822df816633dc0edec53ea49f13a7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c4bfd9cac1684126d074dc0de00aba6e2cc4fd897c34179150d110bd4e08960ce1702612e6c5a5aadd67f302617199eb20a30677c8bf5db09888e3cb6735154	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x70b3b90772a53e37b295b57a9bf6943398e6dd973ee6951eec29f5768e238b3750a4ed0196c93ba500ee02042ef5d0535523260dc23c53e0c6ab97827f9ca578	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8a286975e25b4404026d13a582073b1905e7f54602942037cda60726254b999cbafccca5f8320e7fa73184a54eddff3a190980b3de64f0ddfe90b339ed54b3a2	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xebf28f0c510e67f59bf86e3096f3124681b8aadda61d08f5d1f5b2a98893ade56adacc3edffa6519fc1d5ed1e4ce9f3c623f19d0679945d3619574430b4d1ed1	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x037e5c8717b226eddfa4c64c79c7a9b6e96e66257efdd100ecd81d56c6f0b76f0a8e48ca119c6d92eb1e907054a43166cbc41c07628ab31ff6b87d7d75f2b120	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3d258ff1ec0ef3c281596a6a75bf469e170a05997430c5fa5a820a7dacc43bdce8974f74cefcf45ab182cbebda48e61dc384d40eb8f346f04f35ff57febaef36	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1aea4ea341779da1c9fc9080c2bb4057d4ff0184d6fc7d0bff88ee29525c1db524f7c00c94c2544daee1b478057c765ae995753dfb31329eb4062ce207224253	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x903254a2bdc54e3a99729998ee70ef7d17570498a996a6fc5209e89f4e4bb447afc78497fb38ac04a80a6a83ce5f717e049b820311ce5349af4d0bc3237033a6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7318fe6172e4a94b6513bbfb4a58ea76f182b41ed0fee40368e33c690ad2cf605ecefc58a99818f6a58a1b6f082d3f69521c19630279af84aa6c8f3fb0fbb734	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3bb0f2b788589408c05a524d8a945839b0179c53fe84b0b9c34ae3799abf7cd10e39577810358b3f530f882211b208bd4918c1eb44b5bdcec2a5d2b75a7eedaf	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3897379b7e96727da715207465907b8f7e6be6ed2a7ce4e6de1faa313d26923a28a48bad1f5b236e7502b294df9f10f2c87f31b471e273067995db3d6be67386	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd0f6e45ef2ccb2e528a86c8e67ab8d91db649734a5bae5604bc020a893e0600a518182b035e162851f0f6b4ba239419a0fff858ad9c77b906de93f6605512d9f	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcc495d1992b8438d7ef83656c3f1e8866a586061adccdd65f5b4a8c5018b613e3bdf954531d9ea01ed1e8499a64b750337b99ce5b8e7ccf0d61e91ba69dd8fe2	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb7515b399b3acf94dd1dd6768df12c6553246c2608f3994936722fb917c124e2b938805aa4986839e0d268fcbe58423da00b02adda90d336b8806a714e7f6f35	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd8141156ce472b5491b1647865eb72101954224689f192e6da438603afdf0df8635f87bb804f36882339631ab0bc0fa1663c7a79ecebb0d3acbbbfc8e4940aad	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc84a066381a8aa3c03200293aa7f7417b1f9214b09e0fdc9a208f947ad0483a77e6bb25dc68d9246b2e3882f235b6f69979150448714f21b3cae58912919e273	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe808bb2e7b69d10cc0492bc7479639665a2ae7adb325017d83268e91e0da8119b3135f21609de2f9176a920d1d7125d512104cde06954934ed358242a79be260	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf95e654e85f171efe3ef051808ef850db81cb4e3b09929289041eee4f7ad45d757e02e95d8bfe1188acfd31f6ec57c4c98e4538c834ef6e575709fbb46e6d18b	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6990ccef0308027378b2e8d899745e1e7d14608fc021e4877cdfcccdf8fb0c82c5689e60499bc74e21803864d932858589acd057a3bda814acaa3874a41ccb7b	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8338dcf61518e224872d4ad87b0800329cdb90f19c9ca17ee5fc5a449ce5ca9d0b2cec7f1de68a179229cccb6d7ee5ff49d4063602283dfb75545197549d9924	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3cba28d6efa94ee3366af2a967488185fc8c8e1cd8c4e3546b133a89fbae3027c874aefa8d6aa640b39b5f97889dae412ec6e6ed6ddabc5f49e96bfc55e32b54	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8696fc9ac5a27062b048cf9a04f0e404e9b2f5798b7c47b96974b34b39b4d0254c9d3e6cbe342df63c2ec3a11b6b39e7dbc24fc3bcabcde7bd40cc88abf29f6b	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa19be3485f084388bbb62a4e382cae2c6792e5d0a029b4b9bb5cb73ebc56e37ae22537df09a7e73216de693bbf6dbe6fe4dbff8405e87668f65a8ef3ec4e4124	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc592b4f40daa0f4273aad38d4238acf4dde55e4e0bccf1b2e3993ec7a6fb0bf93fdf6bfeddb4b32e73d305859cf03daafb8461f83f5d777619db4efae9800b5c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x440bef1be48198df25f2857085d1608831545d6372f884bf44ddb08e35934fd9f1e17260ce97900ca37fd534eefcdd67c1ca3bdd250033239365b776b0193d6c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6ca60a2951e80125a43d96e8763420a60ab3793998a8912f704db83c9b52e8cee47283425f73999c1b44325e955fefee1d04fda8bd0edb71ab1f5e8e172b3d7a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x99058eb5afedc239cc510b68ff738c98a8e936754a49a59cfbcbbabeacfcb5079d1d5e48305ee0243de5a392b5700244dea2070a15527759a4331c4d6ce3b5ed	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf26ee89fa029ec68ff908a79089c89d77ac9bad3c7e52db747053e75e2840a42f073621d699cacb7f5c07d6127d2cd62593d2b2fa230f0560f97b9a7132809f0	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5df6191f35c18b94ca4eb3d9f13dc18cd9c93102825e4b4c9631f34c8324e2a7671362e1b445cfc66e7eb5d0ddb31614e4808b4209428fd1548a522e9d868575	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9ed8c15f8269b43a0fa6b1ba33b4552a575c8dc154a6d4a2aa03188917e293f090c92410b3955f33dff467e24df30a6fd62b6754f0cbf4735460818f3d4dab3a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd91288bc07051b3527e13535d3a52bb779af215b4fda1411ec1a9a47cf572e9e5f96901e5fed9f8c254cd74f9334c6612e3e16b97c9327f87f0f93d79ce3115	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2fab40e70ba5786aa36be3f21bba3bd06e554302fef36a8040c49a5607309a26f5d174ab36f456ec9aa3164a29f039f3b3e88e61ef35e646d23da149aa324cb7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d2a80bdf692f9cd99bbf9047a9da203069747e8361b55daaeefcecf280c8ace462a12f23b3e02846f42ced2d6b5caf2afa6755b236521b68a58f6aed0b98dbb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc67ccc8253176d098cd658540a78b6e62dd2d00950825e3d46b1c95441c21dab18c605375b41faef7ef3a78785eb905fe59015b66ae91ce9fd2ab3e9a24e0467	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b2541ec9a406975991e06f9dab462948ee13f1cc36c2ec660cf18a9210fa3d204b24cbe32341617042e53e0ce4a1cabfcd23be397148179018d6b4f420da3f5	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0db0dad05f784815367edfb23e22a0c011bd4b3220fb3469bc442fe720edf8762a182f6bcfb9585f8c7e2de23930f04eeffd86b47103211c6f7bbe57e9d159d7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x74f8440c43010bf88517aa04c9b4cc488d13159dfcc9447016ce3972903cfd046b93a16eb5e5102283ea4935e4f7762ca3b8eae2244e36f57b317cd5e9b9c5fb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x38a6b935c6861bccaa321a15da7205a502dca85fd5ba916bcf2642bd410ec58e5e3a11cd6320614868e2b825187c07fc6bf98ac6ae88d43680f34c024afafc19	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x638c78f326b22aa7cfb37e5f0ca000649b8d854f17af96cd19c2fcd902305df4cd642a861601be7655bf7f3f3c2558f471da4205a0c33afaa840bc014a70d27d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e29a58cc08d5ca1d87ae4657cf51adfc54b4630d3937d6ae4bd5d70c55abdbf763c6529d2b60cee92401b3f4a2f6001b79f8c06a30d9ace6f725f1063466b33	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x73e0971974fb2b833acd44097b462071c42441deab1b6d9d025ef5598effe6c5f45cf016478c96667e6cd4e63dc5e393d8bfd37a078c852d382292a1c7958e29	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc26a77580cc6dd236cc79716120e159eb9c18df56e2f10f8bc1c6786479d6c3d683d477a795c6c96fa79779693d8982d272b0acec1c9476115cc43b740cfb885	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x233605bd0b92bccc1ee38a536a4c0b13a90b50aa477983163238ba179f48007d9012bd5cc8fa7b6d0259379b06304ed6bd2cee6240f19ac6dc9ace03439c7da8	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xffd813a67f9711aa2ce88f8155886936d4d3279b6e5d563380f28ebab3e258cfe7ef65c3196e9827e96895859ef57afdda65046f99868770de524fc988337cd2	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x47893c0c04489906472a92a43ddd3997b1840eb3e300acfccde421c5bdc7e7b20cd2ac615d635de75dc10f3a884031eee2091edd6b79590b09b82a99c19e47a7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb547496c253c1abbd768a83b469d1934f50b71198af75d8810ab5c0c62f31e9f57729a30213c048f3bb7c108404e9dede00b2401602568aa4f4cfb42b09529b9	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x217d04c57da1beceefaf0986bc1efcfdabb15e836b4693917a0ec2fd74f0104d7d931e3361af67a5343ace8d689b7cca36d2a80646e91089c110c4653e9aa6d7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c885b207d21f3ed6f822086850311fed83e6a4b217d8825e3248023c7d2162fc24af2b8a0b77e4fed576a8f22ed879fd2707daeee201c786b6d6b12f20298aa	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x13fbfb34c715e4f1e829be83246f64b429944166d2d1fa59b4874752e5c79dba7d92e385a76804cee6543700ef726e732df487f36aab6a03b19c4f2f176b1638	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe24896d7189e85f06408f3be2d11b2aada626803315f88f0d06bc862b8f0c79fe285f0025f4612a48b42d8924d2c25688fce0d9430dd0834e35f945e9c3e92d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57bb44c0b73112cbf9de6e8deb9569da2f824a2a46cff90f9640cc419b42fe124b4a0d44db67c4906af34722ee24ff5cb763c028ba5336912f216cdb361f0031	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd4373d752f9ba15993bfb0aecb32ab4e3bc327cc5b2794a77f469b498f831262a27d9768d29fb0c7a7e284527f84d0f46dd20ffb574ea0667e62ac28e720ca06	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6380543a6fd69bc94f4b7dd518a804fb33d6de8926312b84d6c232912dcfabd84cddde66e83d5de90761c54b78b0e7602bdce8a8950f3a53c33b2f5c6400229c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb942b589aea7d6edfd96e0b37d3922d7ab215d3f92dd183da9dc41255278ac4b26430bffda2edbf484263e1109cc6de211406e8b978be1b59d16ac1ee00a57cc	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x71e777142b55e71e65b259cff962ab1519e2cbd8d812de2c4c857866879c4dc76668ddd9f05eb750023212381c95b7b8082cc50b1588d697285fd7a64f4bc3d6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e5d93ea18f3f67f43d98c78e4c94664deba06003ecb282d117a63423da57f8c4dacfbec13f5ef9ee45860fd21cb842f61d548d9d359431a96446bc1fa4911b8	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fdef9dbb0dedcafc35a659420632710a6d6cc0ba7f3c56d67eacaabb9c439888bdad867ac6194cd504c647dd6e1664cb4354a83239b15a03f4de90c36cb22f0	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c7554c43137a7839a09d5c134f57d4399810f21f1bc0026417c6febabbe1c6f4b4a85ea33c627dfc517fe8688171fb569c402030c3a9d14467f7f47b0a8835a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5948a51dbdafda83f9554b34e94713b4d03bd592bfefd5da18cdcbd4539449ad1f140351ab9631f02b7d39e1ca508d552214b42455ebce1ef2faf5ef6b9e644d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc3a43e87305634dc7b55226a877487ec31fdbd39893aaa0847c47bcf15a2404bc3a545295b498014a55a38e3bff0773e7909c609a01357decfce478e4ebf8e9	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0674cf4aa6a630470c119c953e93f3507849d556af4a163bfeb49d80eb81ca4f89d754e61b5b745a90af91e73b46dbe29f6fead7e37e92ad28302e160c9fedb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x42bb4a19853a33bc69441e8e6e74b2c9d7ec2f8d20d88904e7f28adbd22bfc8f9df4ed53d2fe238be2135d07dd3105cf977201333d72adddc23b3e4669871651	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc195261ead0cb68de5283320700a6f1c0c4d653a8ae7f8dbe0846a6b2c702f3e4fbf2b06d153de65b2cc955f882536a1d1ef126f456e24b5e97a99ca3d34201a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1577818367000000	1640285567000000	1671821567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0f75d15967837231674447ae50122beeee3a494931b2027c7aee2b0d62d32b4ac9c3e6df4e017f048b48957a912f75fe5b78cdbc6b25bf287fae9c7ad5bd752f	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577818067000000	1578422867000000	1640890067000000	1672426067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xca8d032ec5604b9be11c6ddc053da0aa84c8660e03148e877a8cdd695defdb648907b1e53ee68cd73689213e351069976472290c4e0a4002661105457efbedba	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1578422567000000	1579027367000000	1641494567000000	1673030567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7f9fd6fb509cba16ace7d4c559be5318a98dbcce2642babc6fb124ba6344c22508b735851598dd6b995803c432905e67507ca1bb46a829c0e9fa91b8c29ccdbf	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579027067000000	1579631867000000	1642099067000000	1673635067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xed32089a57e679e257dbd773c2fc95ed1440d93d12b36117f529f5e91f57f8b4178815e32daf83c674ecd790963f7ae6e4b1e7c75b1c9bf300033c895faf8727	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1579631567000000	1580236367000000	1642703567000000	1674239567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4b122f5c099cfde18cd4aa80f5b052c87e1ead1c12c117eb45ed11974b044119b4e52bb71a456ad2647f3d512cb2c25f4d31084ea3f6327f4c2c3f376168fe88	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580236067000000	1580840867000000	1643308067000000	1674844067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x06d6575449756dfc1bada321114a2b5b62a31fe91b8bda8dab4ac53821c7a0c0a427f1bc377e248e4bc9035dabac411560e49be4614bf7af12ae4a57a5d6a432	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1580840567000000	1581445367000000	1643912567000000	1675448567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2c70ae8e78ceee750f77acf4f54dcc698f4f3c073573bdfd7f116bf46deb108bb8023d6365240ec67973b84b051683e4610bf06eb9a7afe2b665dd2262074174	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1581445067000000	1582049867000000	1644517067000000	1676053067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc729f3b23895cd6ad7070bb95c32270bc4dc5f3c9e0b88072babfbe7c94d0ee74bfc024c91ac4853b011ce852f46db918cc36e9b9a2f519cae1250500e68ed7d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582049567000000	1582654367000000	1645121567000000	1676657567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1c263ef12b19ee36a7099449973d4f57e35cf7a07a17d422e0aa14a0a579d705d699ba5f7a227ff157da18afd2ca9e2940ddb09a9d90dc273c01b170c3b87e44	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1582654067000000	1583258867000000	1645726067000000	1677262067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb11480a817c7118c1b384466eea7c83de5e1b0ffb416300410f204894eba8f7552bf0f42270230226e9a7d50f0e92fd67cadec1c4108d862730836dd5820fe3c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583258567000000	1583863367000000	1646330567000000	1677866567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd934bced42b71ea01768818cb30767d0889127600006d2d41efc2b3d3bab37f052192fa7a085101d61f06cb9b779fe5d2c4cef2fd7a15bd4f9173e049b31a562	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1583863067000000	1584467867000000	1646935067000000	1678471067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x500f32f1b5473294840854952811cc0c091a4852d8fd270060b0230da79a86d78ca842d7f237eadcafd6e61be06df06d810f4ca64048857840ad53aed921744b	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1584467567000000	1585072367000000	1647539567000000	1679075567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x77f5fc002fe60657da6460288524c4758e22eaa140e6a2e45cb94f3b2340b9265529dd667b9189c0f3200047ff80a1fd7a19fc3410ac088ba65de59efa2ef16d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585072067000000	1585676867000000	1648144067000000	1679680067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4d1742247764294cfdf6569dddc60de89a8631911f0c3e649ed3fe96edb8d5eefae165bae7dbd35952bebeee0acbef7a3ba096636e4424b4cde6fdc651f95a02	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1585676567000000	1586281367000000	1648748567000000	1680284567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf26516d6b5ca89888faf4944d8c759dd943cbe434722f165c968d524178f59e580988d5dc7dcc5f699d9912333c76ffa4c171ac84d371b7e38bc8bebd3370546	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586281067000000	1586885867000000	1649353067000000	1680889067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3e77b9d9122f7add06f9b41551fd9696dca7a2994d424ebdadf6956e08805121d787532775101894bbecc59a30829f9a181e1af70c68eeb98f5fa771704a1520	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1586885567000000	1587490367000000	1649957567000000	1681493567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb07b4daee6fb5fd94cfa4b795aade4a1d662ee0c22f0486b4ae083c6bc82cf93c2b8e652255f1932ece1a729c2dbe2dd2b9a37187643af0fab2c272a0cfaa5eb	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1587490067000000	1588094867000000	1650562067000000	1682098067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x21413e7a2dd39a3d6afe0ceca580791c50d14314f664826078b2c7fa327146805713d3c3879580e29684d89aa40d0989feda3749c75d2a1aac723a1720165e6c	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588094567000000	1588699367000000	1651166567000000	1682702567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x890583b30eee2ab6ccb48d294d81f9b4ec64e4b23629ece467a0474938647dd919d678a36a1528afb910236d474ee6c03dad48aafdc76406320e3d4fcaf5430a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1588699067000000	1589303867000000	1651771067000000	1683307067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x10541516790854efd3343224824b1a1620575189b86a2471d6124d88a87fbec5b49740544ade06311dc229a74ce2a3d2d460c9590e13703682b9580bce7fae2d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589303567000000	1589908367000000	1652375567000000	1683911567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfd01cb6df1e985df157f4757c1bf0ba652dc8067c9bd0ee3617c529b5da2a390737f2b17e792308f78089b0d7008d333857cfb416b12b4d604191fbb3c1f1dc3	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1589908067000000	1590512867000000	1652980067000000	1684516067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9b44ede887f097b306bba01468f944a63afa2a722bad5ce055e421d505d1aac1b9108606cf6adfbabea170609ed83b2c65be23966dcdc6a95835c96e404071a7	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1590512567000000	1591117367000000	1653584567000000	1685120567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x841cdfbeb433ab9efa14dd68623ae51d6ecf35e4641834a874f19ae3a304e0a7d78eff641f843631d4cca3895d5318d919add0f91e6050e59de8f8ca3e5ab419	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591117067000000	1591721867000000	1654189067000000	1685725067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xae883c60cf2bf17f8b21d7ddfe4065d7ed866e3e2beb7092fa3586efff3c848dae4a135fa8ea712796fae0f0eede7a8aeb957ac5ec1e5a157d1a9634b18bca87	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1591721567000000	1592326367000000	1654793567000000	1686329567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8aa01f7432b1af17ad330d8558f5c12cc60c1df55290381572d4cd42077623facf9588aa2f759124288a874edc44f6d915c2d5164c2ed069c5a2d7818a7b32d9	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592326067000000	1592930867000000	1655398067000000	1686934067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x321b5310b50df669991ed87cd3642e5ef34eecf663bcbbd7abc17ffedff1bfad19d97c2c2d7051237cde218f6401b1948fa867f000112f601b413bb6654f927d	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1592930567000000	1593535367000000	1656002567000000	1687538567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1cadb0742ce6bc03393237eca505173e048dcd246c02f973565c7376e042e4466f4387c8513fb337c770c407b57bd80bd7a5a751c4c9e61683c32dce5b5559ad	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1593535067000000	1594139867000000	1656607067000000	1688143067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9aef584b806af578aeebfc9ec668155a7ad7dcf42945ce2d70f92a060c44798691502b11fe953662877ca99e8a5340db68073edfeb154a1b9c3f36cc428eeeda	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594139567000000	1594744367000000	1657211567000000	1688747567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x10acc4603b6ec613ee0f0e7ea8f43678316ef4815598951f8f879d1d444c62784a9e900dda5802d320c6368b587a56bf4e2ec1d524ef7ff965af3ef7560917a4	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1594744067000000	1595348867000000	1657816067000000	1689352067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x37fa0888598d414b6a825f16ee34823d08d6d3671a38cdb49e030a5a7372abc43aa34923dd2448b36d9d9a6891a6e8b2aef36c87bf3dcd43c24107d1abdfdce6	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595348567000000	1595953367000000	1658420567000000	1689956567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa1dd16c93d424f37c865b3378cc680b80d6b56fee11503d612c465773314145c1a25bfd322fc4846b0a44c5ccad8aaaa962ccc4e51a5ca011d5ee188ffef6dd0	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1595953067000000	1596557867000000	1659025067000000	1690561067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfe07550006655d025eb986289263a52cf381ff6df1a7e3078e473ff08835006eab715ae6d33089d57555685273b5374fc18557afdaf95f9bc4be812cb57c560a	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1596557567000000	1597162367000000	1659629567000000	1691165567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1577213567000000	1579632767000000	1640285567000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\xa605fa477b1454ebdaf03b67fab73f86a380d8882cbd0944b8b3660313436571c2b9630199d59ff1e1b1966e75aac9ebca3a65e5b84f2ddde5fc57e60b0ba308
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_ledger; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_ledger (master_pub, purpose, "timestamp", balance_val, balance_frac) FROM stdin;
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

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_payback_serial_id, last_payback_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_payback_serial_id, last_reserve_close_serial_id) FROM stdin;
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-24 19:52:58.15428+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-24 19:52:58.225973+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-24 19:52:58.291981+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-24 19:52:58.35542+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-24 19:52:58.41988+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-24 19:52:58.482845+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-24 19:52:58.548626+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-24 19:52:58.610998+01
9	pbkdf2_sha256$180000$qrsIQ2E8nwdS$8t+uphHHvoTsOXin3+gpRiMypDwIr751u7OHYYCvK1I=	\N	f	testuser-HTjCjYtD				f	t	2019-12-24 19:53:01.224082+01
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
\\x8aafb3aeba3efca982678b08361a7db49dd0a3c08f8e2608e5a6a7e7ac365b47c6fe90f9f0d53a8c94a2be49aa9a9179d441ed1c5e1dfeff1d59cb5d5b97de26	\\x00800003a442513ec4864d1f92c6a13cb7fdd8227c6e4ec287b78d8e1523c46b52019b914bcb2c29833f95f9f5b64f240e2fa2e9efca04441a14152a80b4442a5d02ca2b4a832eeb05f00e3605e18fb159e5123c6f6722aeee9435d7d8564a09a9a7ac62d3f91f6cc90e563efd765b0c3b2c29b63e2099e6f74558ef17a3f59538532633010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xa24ac1ee4b290b37659c41efa687b96fcb74839ef6cbb65834b3651c76efdbc3586ba0a0de8bcb4de5c34defda5dac0e9b528caa31c89f7c564355a26290820a	1579631567000000	1580236367000000	1642703567000000	1674239567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf666a6e694a1050c6937075cf2e8d32c0b07ef07ca7cf430dbcc8dd9abdd46738734faaf2c9bb2b123b2064b20118807af648974d40ad124d34c65735f38f30b	\\x00800003efd200ef25b632046ec55ca82cd678b916ba95243ef2fe26305cb3e8307a4c476600bf107e1daa4053e995c1a0573495fe5cc9b01463af4850ca5cf87fb6cd9f8628ef064dcefcc0ac1850f96866341bc574ede15e9d8c98d724fb0911abab04154f5260a0f97fc3587b8ee45bada374a2544c5765c46178550d937d3693d1c9010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xd1cc1eefc2535dc3b96699ab7036dde1f1e13dbf81f6ec14cd1c43810ed5fa363c6dbc01a0228af54b96cb1da2e38d911ee382f3e13922eec8e295e8801cea04	1579027067000000	1579631867000000	1642099067000000	1673635067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39bdad342b1831e6195c2652e40e3dbe1e932bda7b08382df1a2a5aafddffaaadef706ba399bd76a442faf1757a30e1dd1e3cc0d955f04bfc870e71be6d1a034	\\x00800003b5afb68699107d42066685dd2d6aa52692786297b69fc580aaba61ad8c028c812f3e39dc73f111ed91ead4098cf15859624c9120033352f6fd54a35d548802dc15b9b6b37e745bf13fa7cd1cb72fd4047e966e09ec177edc716f361aa13e2b7500815546c7c6ed8f409c9ab0e5579e85258d697b8b91723a17777b33c61a7d2f010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x16d30022d2abca803802c272542433b39fc2d1beeae1d90fee233df349ba0dc63fae3afbc0a567c7a3b80a048539c4004b7e87f8ee6a798e42af6c67f836c80c	1578422567000000	1579027367000000	1641494567000000	1673030567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0883b7e676476ab4ade5590ee39b22ae6690096c5fe862100d5cf92cb22ec6b83da6cf619832d85ba774d7ea8a2123da0fab13c497f59851099ef1f752ed94dc	\\x00800003a410cb81813700e74f025c817353ddee08a2f7a27665a3fc1416e15f4a2c9e20787bc45f81760c0d9e846c51e7180855fe72553a2fe69ae6aaee758219acfefec9b88e7d25031968e166f68b593b55f4ffd25ebd0ae3b7661dbd7bfa888724699dde14ccdfdad05f349a9a02055bad15d2585c2984d2ba837e821e4b1f64b729010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x2b8627fe6d27f605167dee393bfe52e629e4e253f856406007ea5344dde6c019f97e0e5baf61fd7058afcf4a74c6c996e4a5566c4d61df442ff22376e9213d00	1577818067000000	1578422867000000	1640890067000000	1672426067000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x84391feabca3ff5ae3957f42f599650d4ca811f1abe095d0d1b6133fbe47522f440c5eaecf75be31e25a4aa114b145c198e109113fd60331778069b294d0d4b4	\\x00800003b7d87adbc6cd24622b84e44673f5afa829606909c6c7882303fcb670dfbabd7a9c2910b1c1332546f8104915fd1b8254bcf35a0b084f86b5970d264dbed9429b97e8785d79071842e3d75d3f9d0e3d3474e420aab1ae46112ecc7a4799b689030d072ee78423f306c12063bfc2cc54459201e23ab3a4cf956f6316392271a371010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x1e93eb2300489c967f2b3b59043e80f92eac02723085d1eb430dccaf83fcc0bdc1c28908f70855a8e7018f269b91ba2bd36d03ee57afa92575863705d0629601	1577213567000000	1577818367000000	1640285567000000	1671821567000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab474598aac8d361f68d596cd1cc3bcb2a69d57d93b6bf691f96fad54d5dc931f6aff0be07501a7905802c002316c32bf333fc2badfe6b14a0fe26a566870f57	\\x00800003b5a60ecc9eca07d59e04fbfe5a9fea7c2f9d357ab589062c1cb447fb58e9353d592b79d6e71fd314463a7e13dcc26507b3d09e9f18090ee06030e280bdf8f6ff89ff6c8f90b8252f3d3cd577f2cbff6c250924865ff5691f0166b0077f9cfcc405b6ba7d0ce7a4376ac93c58a2e9032eceb86cd17183b658af6d7b1c44c14ab3010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x4cf0fbb4c979dea0ffe9ec8d30657a3e94a8800b50f38ef52e7b8cdf04d23fbe0954ae5a2aa251967857ed489b32767c9adb4f26d2e178e4075d86899364e008	1579631567000000	1580236367000000	1642703567000000	1674239567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xebfdc3eecba5c5cc6dc7b02f56805ae68e3e3323b5156bd32a2e137e31afe2d147540119b9e24d83fb03e1eb20fe02b6dc8e311e5a18ea18c008febd2b9fc565	\\x00800003bd103d1aee7855fac632d6a16fecafb6700ddd18a6d93cbc0e2f2d661970ba5324834c9747345f4295e86e91ade97cab474fa7b388686399fcbe187102525e04598cd649e5096f473418ef316e00f54a1903ec99c2ba327f377e29c9b19deeca327d51e17ae63edfb7c9d917d8b517abcf60320b95fd553875deb61b46bd754d010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x1d380aec6c25f30088cc57c7da60afd5fa4979e8d6009bc1751050179436417c5eaadca1dd9c2c9c67884d417423800b13132ba5be364e3380086ba607774d0c	1579027067000000	1579631867000000	1642099067000000	1673635067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22a315624aa89b9367f026281575830dd8ed12fa466f194c0088b8efc8a35ce8eea3c46462ae6c79ddbd8164f21076047e5ec60340a7f035d744e01f67bc7a8a	\\x00800003b9c14f5931291cdee70ca6d4ac4406affa1aacd367fc5b42aa1eac5036070901d40a6041a75aaa554ea8229c4c146e121f2a2055db3c521bb63f0b136a9ee2455abd14fd2cd598a993be481dfaa2e570dfd936e0540f22a73504f625040183fa8d339488517d4f4e07be0a7b62edde3568678f31a5e6744854206451cff01031010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x2a8aabfb68ae61f91dcba37a7023aec29fb6b5e05c06dafde5806a900374f3dff691353517066a399981d2bc53ea1135ec51b7511947a65b3fa03cde2ad1560d	1578422567000000	1579027367000000	1641494567000000	1673030567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x75c65718532ffa4675639487b6679ed939cc368da632809e7559687969cc4c7b1ac9b8c72fa07766ab0015ce83e6124367e6989f883226312f04fe53dc586b7d	\\x00800003bf777788cba52fda7f99d6d7afaa38eb663e307ccfee8efc062e2eaf6a1307b13d016119689e570056644c024330a72c52e4d10f9ed0551e2b83d3dd5c49845c69b86d3760c4dbc188e6ff68971d9c653d0e6dc83673a39d4d931c50edf32d7a497868c916bfc8c04308c67f5a374556348a21617dba916f1a68d29ec1fdc14b010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x6e77a1e75d00f9de53a2fa933446cefb7e6114fc305c904ce2066eb3d143de35aff8b7fea1aa9bf8eac016be943c8da5819b61b27c23cc1e3dd6ab7e713f3d00	1577818067000000	1578422867000000	1640890067000000	1672426067000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x158f062de0baccffbb945f80194acf9de09307f343a43f028d752d15e9ef7c067c0ce2cc6ab34b36fdd9de7a6be3dcfcde8819fc162fcf0757347d4b258f274b	\\x00800003badf61d66227140f5dac4f77c64eb3334bc0d4534d7ca16fd41999ffe5c55eef677e95734d764bcde77012d0c124d9218360e8411e01991e39fda2d85aa31393cfb7460d12a8bc963ca17cb4e6ff1f6121ec39962065b45801fe2fef107f69e0448b3151816161c97888d3b1210cd3803ad87011582a860255d34b66917bc339010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xb451f0f57f8817cc82a5c1eb64956383aaf533d4a4c0ac7b2087c562dd9e49c5f5da1ec04be042d9c2bb48de718bc2783f1ee555d63ecf9c3fc99f5afd0eee0f	1577213567000000	1577818367000000	1640285567000000	1671821567000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x694864a41aea2372d2f96866690bc8ea4001cb176fb7f87b3e345304ac461fac9ef0d091082bc80a636b04106a1e3e39bc14de24f7abe651149b0f73eac45ba3	\\x00800003b6c726685e94fd0dfbd0848c0cacfe3da718203d4c61c17c55fc490f8a2699cfad6f458beca0bb7bdcf492cf6e9aff1864c7866851fee977161acf5dfd0e1e4a6f991cfc7028814781d2581f408ad9c2e74c122d88a2c132291ab2ecba0c6a4d2c87abcb97ca55419e8f7f67335bc15e12ccdeb73a8a83edbad68d4032bd0391010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x62c3fc2636fa254e90086eaf62409de5673b32c50c37a57be63e4cd50c1b74f6eec79b17a179ae08df81fc7f118caea53bb82310ed2ecfdbf2a81d8102b03a08	1579631567000000	1580236367000000	1642703567000000	1674239567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a2d483a97cc668f9da157246f0821194b654332d53cf42a5c2797b669ecb97972959e930810609294164dc2e17ac5488b8ec59a091c7b63c9a54602ee33a556	\\x00800003cd5937e317b864c7dd4da2f777aeac533b4484c041f7a9b706e3d3cae5c0fc31e937ccad8f0fafb02ea4719bcd38b97e8283de740346853c9352eab390919416225958b8e4e5d8587f72356a4bece69f95ebcb8ba4b748dbad510eb357726707982c1e6e8bfa1aaea6269b75040c5697c55fd608446d89151329bb34180835e3010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x913be558fdff4aff20c1bea67d5d6b2dd0a291b90d297f3dd9e8c08f56f4c9473e33c0d1e64b58ada9dba444a11fbf8c6a999a222d4402da302f16ccac66f900	1579027067000000	1579631867000000	1642099067000000	1673635067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd5ab082d4933c4531762845791e87f1eb56454842ed2716fd68722346b2ca0d7e2ab1727af6571ea61f46b05e058261eeec2d7d69cad11df8580b9a91b2d95e6	\\x00800003af9a1fb3d5ffcb45afb7dc364cfa2075fe33bd6eb506563d02503419f31a2ef6c423b20468e3e0214171ffa4c7e20b2c2edfc982f53c44252ae92d481ce695af597b32ebac6038ee5129a759899e7c75a8d74dcfbef5ba7e54bd7da1b322d24e14ba5d49dfdf05a6e37bb4e5c5f8f11c39118995445ddcec4ea8d91bd8f5e825010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x2384484f25c2650288fd07370c44c879d8e33c121f977846cfa93184f0911680b4e59acd9154f97742c6431c320320375086e3d4deff36d7fbed640c0856d303	1578422567000000	1579027367000000	1641494567000000	1673030567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d110dfd54734b5816afa924365ad9a586ca4c17352f0cde9bbc4f0fa592239466c799194e2d057a51eb38e4731fa8ff332644c0f511becbc469532621952059	\\x00800003cc28bc47aa52cb3ca5b01cb92835c50999e0a3ce776e988ad7319d33d648d4f437a12b512200e2f68f51892d971e52af2ad4f27700b75d703ffb9f7df2dab8fa5df38cb29ca820e1f65f89b590d11319e0738f9303d6e32c88e856d9ff9407d2a9030ede88371703b3186589f05689000f0c4b1661cfd1178d226eb1571d7d87010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x74f64fe214437086c9cabb0f0b23556c0e7a840c14d25d72465dbb4a9de4118bad02e59179be623bf633533deb747f3af51d3958f8fc72831399312bb39a0a05	1577818067000000	1578422867000000	1640890067000000	1672426067000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xede669dfa22144c16fc370fb9b3230567d597491f7f2c6d3e789967943f7f967196181b9c2c905f53340b6c04d464b1a7294c88c445ae494769ed8a42844a847	\\x00800003d3af87096c62bde437b76806524edc0f2e5818092e8274e8560e747ca8da92717b2091281d7a0eb0eeddad994b8226bc312aaa14d9bae3889194f33bb0506056c6a01cf12e9815e974dad1a81dc4d206920b23b0d16d2a764a29505c1f0908bccc6742402c7bae0a565200f2ed9c29ef4de3e094167b9be4123c54f2a92f6155010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xd5e07f69deceedc2318a1a15724f74467d8fdca635b31faa13948ba02ff01f185b702a2133343e0180a9fd7e80f598e5badeedd1b32838f7e81542562c854103	1577213567000000	1577818367000000	1640285567000000	1671821567000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x564e1a55abaa059f4ad7c5b0127412a65f06495ad56313e432f3b833b3e9d84046a74b1a2017adf46e06511c40becea20f7c45c9305eb606640761b304164bcb	\\x00800003cfe9323c17e08b57972becd8680c1860e28f23e702532c0e2782818eb36311ca0ce2093225f69b33929b24a8e9ce42bd4126e553305d2250c9f97fa7d0e92762cc45610d1aad4b02214bdacc93296c729934663c02f23757de2bc2b6a771f20272d2afbb5db7b6d8914121c86be31c2e0a2b40631775fe91532654f54c342df1010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x95f91101b569bb62cfebfca7116a2d3955523b421a12f5be4293e110f21f150f3e4a2892bfb9421d130052c44853caa10456aa7a0e0577b48d0005b385ff7207	1579631567000000	1580236367000000	1642703567000000	1674239567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc023d2381915fb1bee2573f43e0eae6e1cb8af166c6e76074713d4947b70883deaf683f1e07e60edc113de600353cd4970df8644cad56f4333bfa8d33a07efe	\\x00800003b8c0394da1bca4f80d15dd7f932cfb4243c441cf7b0b390a9fe5096856d07b9925b5cf625c36164cc6e3dd9fc59024925ae21bf28f9bc25939e5f68cd3c76f8a3c40c8be139a5d0eecb7d51785a573b47e9f31d105790f715ab01b4ba040c85630ec89768d9a3c0480fc5a7a0adaeb70e082d335d03a88d8a747a063b5cda853010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x4bea12bd3d9ef863c350d42a178a43cb0d7c5322ad38204a2f94bd5ac6f540944dc43710c3fa7e3d896e31e9cfc9706db1f6e2192717ba8bcf3bc524ca57b70a	1579027067000000	1579631867000000	1642099067000000	1673635067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x537b4c186a601792d0a671aaef2443bac978002327f084a533c69dddedf05436990f7611f894f6218e41f4bb06f1c231873a80e74a60ac43881e54897fa658b6	\\x00800003d94bffcabe8384262e6c64b4a1649a31e050a4ece0ef3565a94504d9c06125276ff0d6a14e9938f39d78e0f0e5b830bedb71734419857d50ecf3e1f9a612bdb59ce4c66abdd31716a98cdfc49300835464e2a3e9df3555cafe9e1c1ade337b774f8e802b8f3573ab35035a3ef05bf2a8084a49e1a8e083f639b9973107a0ec1d010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x57c216d0cca93d27d71c7c2e4effc35e645edb45c7d9fd1288ac98cd3df3ff65cd0a846e4851e3e85752dc97fc6d64f248d85236479cd577a02674eaf9c13b07	1578422567000000	1579027367000000	1641494567000000	1673030567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23be0b7b4f0a2ee8a807f4d3beb2e44578ccd9d48bf449976f73bd4c9c3e350406401187f55fdddabb8f84213636ecd4bba441b576d779b22cef04829026b3df	\\x00800003d834f3157d088a62b4cfbe51185f56d17ceb9510b1c35001100c3aef5bb23e6dc961ed6642d849ee6521f90c2030972853dc4b7aa85361f4ed0e44a7addd14ce9d2963b0458a123e2d40d96738d414a91ef4549dac493da968b357352829806705a049cb73a928fc63e0e61f63a859f3fada178247452fcbff0ff6113012e129010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xa1c321e411adab04a6f044761ca1c8afe42601c5df61c41b801d7f108ace27144e7e7ff63c800d8b34160659508f2e2b69dd020a5959eb0a2532f2fb270fe402	1577818067000000	1578422867000000	1640890067000000	1672426067000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd47cfc07933afe0536e9537b81c3f0238ce5e7e88b5c57b1db2924679e56b61a9a9ccf86a71e72af5275bbfeadd463a3982e87771f49ecef13c6ab78915eb607	\\x00800003d6e8419eb17c59f8e30d6c8e1da2b03e016dd36e76e9e9b457241bece83f7572cccdf6409fec93e313c3df6d8f2bd21ac7f5f60e7f6ac01778eeb17003340c5289ab0edbf404b298bd384ac157a1e60e540f6fafcb5fa258d3f8d192398b58384fa84db1e652a4a4778fa1fd71f0fa4b8b7100e5bb0ba74eed51f0f394dcf35b010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x6323ffc2150099282eb6ade4d6b4eb0a059a6c8519ed8e39d9e4ad70d08c7d9d2740592add21ab130085ede9b5017069100127246e8ffb848cf6ddd8ca8b3606	1577213567000000	1577818367000000	1640285567000000	1671821567000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x70b3b90772a53e37b295b57a9bf6943398e6dd973ee6951eec29f5768e238b3750a4ed0196c93ba500ee02042ef5d0535523260dc23c53e0c6ab97827f9ca578	\\x00800003c09e7f398605200bb5e653b393936652599c0496018011de4aefd9b0a068be99c328977e02345ed311de330b62285e237bf563d76b57fea294c0e462fc09bbc755852688444961899ed3c3fddce25b5e07ab1936807ae8e7484089ccd8b6ff2fbe89b5a3910ced00dc277cc0afebc4e5f193532146e8d0f20b79cc607e7ca2f9010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x59498bb05b974f35f0f617632c1487cea8577cafd5218e1d1617e8ed32d640d8745183ef362051699d721cb1f90298e7e121553980f0c3f2374a4007ff8be401	1579631567000000	1580236367000000	1642703567000000	1674239567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c4bfd9cac1684126d074dc0de00aba6e2cc4fd897c34179150d110bd4e08960ce1702612e6c5a5aadd67f302617199eb20a30677c8bf5db09888e3cb6735154	\\x00800003e3b819ddd26c1084c8fafcb91217a831b8dd6e9bcf0ee2e37005cd2d211248ebf8c70868f5122f837911d4275a647d9aa70001ecf677a1fa3d979b0db1704d095225b4438452ed9bec0dfb09404ae68482980b7f13533decb81e110abbba4c1dac8846f635f2887382835deb7c0a7d7766cfcba1cff583f53dea5d35a8671837010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x86bcaa2cb7c3b62d7485e65ab3dac5625743b234df099456c8e928479afef1bce9f1543fac151d45816410c871a064113d881c5d108286806b08515e624a760d	1579027067000000	1579631867000000	1642099067000000	1673635067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7c2b54d9d4f8d84146b7b8150c5283720d6d3ea53371499e7858520d12655a6d66344ea65b2866011fb1664c34f0774fb54822df816633dc0edec53ea49f13a7	\\x00800003b17c49703f9d3318a8854e48f19d2c512206446feae440ebe53b7d335de0276e722c7ca1d85fc62978b4c05c23f0eab6b2a1b13f1a1b656e4ef5e19de396bdefb3df4464b64060e2522556f972e32df167506dee66ddf24ea0c8854cc19edc48fa1babe18f682114a6e26ce7b747b07af0f86c9095361de474c7992ed57a5f5d010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xf753d3a4229a21a4001c8f2853c3188007dad381b395c7138b14ec5cd4b4421fe7972f6fa260303697ab24c898c417bcd593b8e267eecdd74499ed2ff8441400	1578422567000000	1579027367000000	1641494567000000	1673030567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xefd6e343b22f86d6d90211ac2995434c918c2ee00989dea97835fd953171307558e2c4fee149e188fad3293f8bc745086b3dd70b62891fb0d23bb196c48ca15c	\\x00800003c79e10d0b19954eb774ed3988e4672f95df47c04b437f344743cd4994dc41687196739d51194dd4752e48040ad22c202fee5dba84a21080c33748285c4f0817fc6152f52d8012055441c0c705ad3ea940bc5ee51c8b127cb5fcca1ca7c7c6eca5c8e4fe0224ba83e1794811d3bf931f1789ed349081e519a63b7ec0be1b7be75010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xd4881ff7f83e43afef58770e4daef8757c236f659d8021b13b4351ff40174206816ceecee6c9f4c4b797d4a65e102be448f1bce6dbc1ed37a4e7f9d323b0410c	1577818067000000	1578422867000000	1640890067000000	1672426067000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb31d4c665d78d512f1da0b98da0ef511dea23c9399ab2e30fe57ac47f37703f61958f212a52cc8496cc8002baaca763f5e4aa5e8ce5c6d8818da787aea15904c	\\x00800003f21fde82ad854ad84e5f817d3a3d229e3141b3814752ab451f26b92896d4d07e060f47b37e58c57291c9d6faa3e64b525cb7349b715800f87feb715b437cd08be7f13b23cf333c02e80c85b6f1449e43ab3443ccc2aeff08dafddea0466a71bdb867873b49ba9cb59d8c17bd9f8394cdf003dc8bad96211077d7ce7b88005957010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x140554f94cd698e7955c6a5d9f7d634e1dc8a1136b1f34239671ace539164188a83ed03e849b64db7fd3b56a8442802ac3c534e4935c9dde8f2431519907620e	1577213567000000	1577818367000000	1640285567000000	1671821567000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xed32089a57e679e257dbd773c2fc95ed1440d93d12b36117f529f5e91f57f8b4178815e32daf83c674ecd790963f7ae6e4b1e7c75b1c9bf300033c895faf8727	\\x00800003ea2a6a449437a7a7e2ede1b5d4cedd13a87f79014fb97cdb653c1de1d3fe987a46342bd790e5f2f9003ad2c871a86cc23fd3c876c5e526a178789563b96163f8752e97d93512f786103f1dc63f3552ca26e3bb094708f0376b47207b09a81dce41471a67c2650b8856563c6716ce740291e2c7b1d092b9a7c37c39e04f86c221010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x43c763a61857ae6f9207849255a48b8d26ca4dc1459f1d11830c461560eaf33c0630fee8a0e5423f44e13fc7bedc64738fb6194eb5ee27ff912dd44fc5d1800d	1579631567000000	1580236367000000	1642703567000000	1674239567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7f9fd6fb509cba16ace7d4c559be5318a98dbcce2642babc6fb124ba6344c22508b735851598dd6b995803c432905e67507ca1bb46a829c0e9fa91b8c29ccdbf	\\x00800003bdf9503b759f3a0f447fda23f161c50f3cf516dfb85f4d7b14c0cdebd409aae2fe7e0a74d151ce3ada8f05c3812e5d8b509039edd827e03731b52e7bae091619aab83c58b332857869196498127570021010188924db802724daf41543c96c0a844dcb9b6d447db8ba26b313d122486e2e970225ca969d8c1cc98eb843949ff3010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x6975aa21a662ea462d95737e83d126acc9fd324d5b703c07ae1f6fcc00cfdfd3724d9534addc72710887f4aaed37625a3abd3fc3be968fb53d4dbecf4f48eb01	1579027067000000	1579631867000000	1642099067000000	1673635067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xca8d032ec5604b9be11c6ddc053da0aa84c8660e03148e877a8cdd695defdb648907b1e53ee68cd73689213e351069976472290c4e0a4002661105457efbedba	\\x00800003f3dead8c630f55b12cd971ab34ad532fe2b0279bddb0a2030759d17e08eb8ff078d08ac315414396063ca67beb2d50127c9d1f9ae8759213280b77db408ec72595a2823a57fee49b70c46184e8fe6b1c119b0115339c7c35ddc3c179f9365b52c0d83f9bca02a79bad9a2937a503341e791da0291261793ed4961988e7cc51e3010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x2ad83a744b732c2ff5588b0c6588381390dfb028e4df432444435e5644639c5d08c177be8ac8978e666f5d186395822ecf18a4410a8dd94d716c7d3ff2a2a60d	1578422567000000	1579027367000000	1641494567000000	1673030567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0f75d15967837231674447ae50122beeee3a494931b2027c7aee2b0d62d32b4ac9c3e6df4e017f048b48957a912f75fe5b78cdbc6b25bf287fae9c7ad5bd752f	\\x0080000396b0cd120df1b7a58c7e03727d9f926b15a2263929aac74a33faaf48b4b34bdbcff57a0b93431f6442baa9a3816b62f70016e4284fba48bc546592369b3eda6d06523f8aff4735b4b04b8875eed083a51cb4a32276d14b23b9c72dfc1014bbe70d050c59f21076b671967c6f5b482cf26607bac1b4861f499e71b3b95f0fe8f3010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xbc785713bed044b53979daf2f199c70f02b82697babbd8b6f5a011caf4848635a61d3f59acc00bf0b00b02dfd8f35d58b4921bbc1933d3611ca7af25a843310f	1577818067000000	1578422867000000	1640890067000000	1672426067000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc195261ead0cb68de5283320700a6f1c0c4d653a8ae7f8dbe0846a6b2c702f3e4fbf2b06d153de65b2cc955f882536a1d1ef126f456e24b5e97a99ca3d34201a	\\x00800003a3a7747669379fa7c4d571e1af20462062f5c57add3239ca3833b60ead3f2354bbab8706ce0f3caf6a9ce4eaca26f1e96362134590e9b3bbcc794161a93e35f00c9cb51d3786672f34ae3944a7ceeefe77eb3d0c35bb65ecc92ce9202648f005c349e30a4daf5b0d1290c2dda448bdbf180782ba5ebdced006f83580f488c999010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x938563b5d0caf8dbc500b150db499d6f69abcb531c05dbc28ff0984291a951c497598315a814f38bb6b74933eb43680f48d41ca4499b4b9b9f85ece37f00330f	1577213567000000	1577818367000000	1640285567000000	1671821567000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc67ccc8253176d098cd658540a78b6e62dd2d00950825e3d46b1c95441c21dab18c605375b41faef7ef3a78785eb905fe59015b66ae91ce9fd2ab3e9a24e0467	\\x00800003bb8d7371f2008502342a11a495a140083559a9dff2854ea12277c2ba7212e7e3a751391b02f7562900778da186e6ce0063bdfe001d6c39926b00c7b9067e4f9eaa867fbc8c40cdd16f37b8a518a18b1d1de9a923d891322ce1bb405c9d1365399e5f5150632da9ecd2ac860dfd0dac88a7ee70e4627d875f012589630868a9af010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x25aa324e62b70ea65d6dcdd9019c325b76fb8342b44b9158a04854d4a1890b3793a0be0d1a34fd0d4b1cb1bad7c2496476f1340a231a8e3fbd02bfed1d08950f	1579631567000000	1580236367000000	1642703567000000	1674239567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d2a80bdf692f9cd99bbf9047a9da203069747e8361b55daaeefcecf280c8ace462a12f23b3e02846f42ced2d6b5caf2afa6755b236521b68a58f6aed0b98dbb	\\x00800003e63a70bb69c12242ef21231e4c72e562a299df08080d3467c0ceef686c34125efe3d1f4d1153423166861f80b7708a0c6c8f6d3fb27ec353faa034a24c45d846ba56f70b9fd0fe19e8f73202206fc6c91794145c6151ffa5e839698682fcdaa119f4f0970014a92c4d5d31e093bbbfece8055112bd96acf95fa05d76aa1a78c3010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x4b278dfa068db2684d07e8d9edce05213c96ece2f3b29b9f8c89306a6c7d8a500dddd94881004f158ca16d52291904d77a5e5ad60887592279c9fce0c953110a	1579027067000000	1579631867000000	1642099067000000	1673635067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2fab40e70ba5786aa36be3f21bba3bd06e554302fef36a8040c49a5607309a26f5d174ab36f456ec9aa3164a29f039f3b3e88e61ef35e646d23da149aa324cb7	\\x00800003bc4d1294103b55b5fb62860a60d301f7ccd296870cabb05b70b4413c80d8adf5ce5494e029d2611ad62610330c35d6e35c6be902301df6249e656902e09bb5e7893ffa21e01b1c564d6291dd819ec2447b1cfacfdfa2cc6e830e233cfd2203de0abfaf24cdbc82a0839fd711e7a7f90b3f30a403baecbafbb9e0fc8937d329a1010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xd01f2c305999b7faee7797fb3284ac164b8585e816fea16ca5cde126612d22d700ccc3f8fa545727682fa049fd975e428a21828c3f68f0cb3326aaf8a82a1706	1578422567000000	1579027367000000	1641494567000000	1673030567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd91288bc07051b3527e13535d3a52bb779af215b4fda1411ec1a9a47cf572e9e5f96901e5fed9f8c254cd74f9334c6612e3e16b97c9327f87f0f93d79ce3115	\\x00800003c8c016b108881e98106d2f0edf70a93dfff866d984eaa4b41d05ce048484f88072a3b582c0665d9ab136193a7cdfa8b5bba28b949e68f277a6a9744e265f016991f08a43f152c2b658875faa770617645075a364683bf4afa0eba9b44b0bba19f0a4351310737164e6e449e111215064835bcc3589449d6af0a32a9f6381d279010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xb68541fa528cfa6a077e779cd537541b0cd76a9ca4af79ae0b9dd349f0272603902b40219fe53d862df413981c9622373139b755b9970b84e0a08b8afa2ede0e	1577818067000000	1578422867000000	1640890067000000	1672426067000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x00800003f99ca164c06f6a11a660adfedc508f482bc23bf82b829b3a54a931907ac23e6108bb5bbbca80037cfe7cae12256f377225dc90fa6ab7811602a06b147c83b0b816e257593fddf7e0966d1a1bcafe980dbd0761ade91ddb1e168eec37469475a1242a5b494e27b2dcbc3bff38f588438a897028cf6519b7c374b6e8cba72400b1010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x2248362906ad6d89c7e496bf12eda464489fef91855fac67dabc67d7298f7084d7328d3545018892135eebd0d2c192d928d6e795bfe5963c068ef563876b8c0d	1577213567000000	1577818367000000	1640285567000000	1671821567000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9889d9d3a8ed0aaed8c2e2970acb9a8e26a361a3866fe842d9f2044bae4a66df10df952be4aaad24e70748eb69387e7028aaefbe41a10328a6d003c4cd5d7660	\\x00800003c1a6c18ea39903fc13a1c257bdefc09a3b2c1337bcd35731f1fcea3f6806c624301ba20988be12737242b107ef584d901b17a3e693a03ba6b783d032f42cf5f4e19545a9e36110975159792b981f06c69163a08147801af63959c4022b7c54a76b40275d7ecc21988a50b2dab61bcd3847e9f70b13d6adca1c8430c9634fb757010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x107bbd4b3c7b6e85ba0582cb6c637e03a5c866c189f78d8becfa8ee8554c01edd2b9cc6c42573e7f06485215a6fab04eb5555b7374a2ea601be1c0479245650a	1579631567000000	1580236367000000	1642703567000000	1674239567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xae99b3efff030938edf2a4c298b04dd7ccca38e4f6fa0c2f4b1602d0d15c0daec6e376458a45874953affa19142616fa2d75f0de8ce25a55a598ed076f5f0340	\\x00800003cf7bbb561dd36d765375a5aa50a2e6c372f5cb45b8967f6a65900794ab3706ee6634f6f4babb0eaff08b4a0771371a6d574b0f24193634a40ffb7a0578789f33ceb312ca92e9e02813b6ad0d3d272c77cef08eabf3af4ea32bdf245dc428f49dac928890339df8a8c87e60b19fca2da4c2e04c9efdce08ccf0d9c946320a1e09010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xede817e3f3bbba97d6b169586669b9c8ba28b67c942af4c57bf21184f452dd61f3e00160702856e71a6423cac05f5f53e5706ac29c9cf152f45509521ee2db06	1579027067000000	1579631867000000	1642099067000000	1673635067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6691bcb806b51cee0a45b9b0a4289248164c0721a5eba43b65554b860bd7fb75b98e49be3126cc4b46b07bb8b79b1f442d616730e49d8cca877ab2d58e1cad88	\\x00800003be69a1a1c726fa8e4219931acee501042ad7733ef5ff6abc411b68260f34214d55a41939da550b47f7dccffc8fa007029abe0e4283080d49dc599398ad8753e9df082539ddf608a4dd5e9ac870cdff3b1eb3deae62d6c46bd614aa87ccfa976999a7ff9fb880e4167a38fde538dfd86c412928691dbf1722acf8e3f17fa0ffd1010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x942d412561d597ce843272ea304ccdf04ad7956f38da44e149ece359cb52937ac2972dec09572307f64eaf17f3ab92096cd809850df37d832fc33ddbf5cb7505	1578422567000000	1579027367000000	1641494567000000	1673030567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3f116e6d55d4ad6f34475c167dd7b7028ad5117682986843de3b3af834fec1a052518c8bb07483dbab3de6a9570375ce96603b1ac467541292e53c5235f1283d	\\x00800003c902fa8a1c4ba222649a882c0d973be27d227a8db3bf98552f8d1a4749e067924744206820921b39f92ded0e29b11a502a6deaf1b81713d95967dc1e1fe9861e16ac23693940d538d4de3f4c4b4636f8ba650e19137beff0ea7b5c82ec2f6c9294ed7a08e75897dfb0c3fc9f1efeff8dbc716454157b38296de90b0d158dcb93010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xd657c90ef464ccef8e0774d0486adf0193f125e6995160a7467ad27c7fa1cb969aa9c37056239a6422a29fa66e57e08e764f2301f8579aebc3aab905668df104	1577818067000000	1578422867000000	1640890067000000	1672426067000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbf4cd487b491cf026772fc54df30424f552dd5c2966677c35fca940791d8b9385e4bc3ee676c969b57b85963b0d84618e605fd26fc1bb0683cc4066004213122	\\x00800003aacd7cfddd3ac0c1015a5b56736a57fc3b2f31b24c8172504b6c132cd70ade1c2fa6fe9eac8542964659fd4dda3846ae35a37e34e439383ba8bce09627eea6739c56bae96ae3bbd86345ae58c7d319afd17a309f910149536bc40b0d67baf31e47b2cb03514ef7b776b7f29e104cd48fe0f70000822771ecd21994bcf53379a9010001	\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\x3311cdf6163ea66e5d54653aa849ff5505538c4ba2a3a7c105259e1e65aa5babd9a64742b7741f1f2231aff67aef7ac5647ffe8e1f5baeac28b49c70b5eb1303	1577213567000000	1577818367000000	1640285567000000	1671821567000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	1	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\x16f8cdf466b0b65d22a29f2f5284e4f33aacae08877fdccac8e799bd84f5ccbb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xfe2482acaea4eaa4ed3603773966f15e823e5aba48019d030376096524416e54246782a22da20e753e10d688a5a724aefa863a5775991b4e949a47eba5fbcc03	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0957f65557f000060283f6e9b550000890d0034557f00000a0d0034557f0000f00c0034557f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	2	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\x56ded3e3f874fca9064c620703a82a6224ed5519c5d773401477b28f2f5c075a	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xa9bfdd59d3bf1104aa2b4914e2c4bb07783e8f0f2f1f1d9c6f58b31f122931de77de65a1efd94a4dce9b93be1c91fb9610eee72aac3a01c402009cdfb8c34209	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e085c384557f000060283f6e9b550000890d007c557f00000a0d007c557f0000f00c007c557f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	3	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	3	98000000	\\x18f628303d508b88400cdc1e5c412f78d26e809ef31d1ed32da97de31300360d	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xdae03899d59b3fb20b838193580e2344a64e3dd670cf6bbbb61acb3a71065b6644ccac2ba7e707c224ce3ca76185a84f477cb8679f9ed6baa481fee2185bd80a	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0957f19557f000060283f6e9b550000890d00f8547f00000a0d00f8547f0000f00c00f8547f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	4	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\xc566a8eafb7c6ac4b1f7745d556ea5f76f5b2b6f6a9207771c91e41033733cb7	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xee3c246b854ef39514e49ede78701653083e2cead02013b4336ec6d2e88652817853563f39cfa3c92918bf390e167e94dceb842f2997746d4b8653929300c20b	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0e5ff13557f000060283f6e9b550000890d0004557f00000a0d0004557f0000f00c0004557f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	5	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\xcfb6b107f3352e0f3354da3f71bb8a1173fa0e9df0f4ea8cd65ba49801eb2089	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x2c1035b29dd0a4f69d8efaffc71e01fcc6ab93d525c22c2f30e335fa0af0705b6789f874ee6acbeb8e7a51bc50adf39aac1f55fd9335dbccb69b36329ce0ca0f	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0a5ff49557f000060283f6e9b550000890d001c557f00000a0d001c557f0000f00c001c557f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	6	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\xf5624da64a392d5278dd96940b5af88a86e9996242c7d4ccca0901deb8cb2a97	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xeeb602cdfb4f64c60b902450c24b7bdc64e56669eea7b14a4cf373809bea12f154518136debf491c6d71175ae4e7b0fc32936b840457690a4d6078316e63f800	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0b57f1a557f000060283f6e9b550000890d0000557f00000a0d0000557f0000f00c0000557f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	7	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\xec0bd9ad7b7adf4add283af4842c4634c2a85621a84b4772d801ebf54ce7cc8f	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x5465dff6f6dc1b45bb5a882ded3e228abcdce448fa5fac04a4ee63a4118ae83165ea002978c34e61322c3bca7c4fc33b817427d0bb609bd6495f3d1586537e07	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0b57f66557f000060283f6e9b550000890d003c557f00000a0d003c557f0000f00c003c557f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	8	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\xe698a1275e6fcef870165ef9021e72134220873a7ca2d894cea4fe1e16f7cceb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x5aeb714a48f7637d67e10688f919e47ae9ca4be442fc6dc8fd0bd7db52f9a2cd340ca607c62bc722a8a1b046a702b585148682cc074a63143e79d26a13f01b02	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0a5ff19557f000060283f6e9b550000890d00f4547f00000a0d00f4547f0000f00c00f4547f0000
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	9	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	1577213582000000	1577214482000000	0	9000000	\\xe992cfb026a8e9a16229755bcaf54f6e76a385bd8eabec0b5bd3c32821d59fb9	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xd714feef6e2a743aff247c6c214a08c7cdac0d48d1b8ab461980eb08ad93f5735e5cfd018330c1c997fcdadf1a987ec2387b44087a741ba477ea2707440eab06	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x1665e486557f00000000000000000000f2ecd88601000000e0e5ff4b557f000060283f6e9b550000890d0038557f00000a0d0038557f0000f00c0038557f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x16f8cdf466b0b65d22a29f2f5284e4f33aacae08877fdccac8e799bd84f5ccbb	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\xf2f75291d5fa1ce8bded228d792662f49eb218bcfd271ba2bea871284530eb56f730b4a0d6e26a71dbf1bcbfdd803ed69dcbbe339d406bd27bc3ccd50981e605	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
2	\\xe698a1275e6fcef870165ef9021e72134220873a7ca2d894cea4fe1e16f7cceb	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\xf667945bd104c0340a39f89baee6056f4aee6a20803e7238862e273bf07987066ebfc244bcdda38d7ed1a9257ae20dcec80fb4b0cecb3a3413d7e326c987cd07	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
3	\\xe992cfb026a8e9a16229755bcaf54f6e76a385bd8eabec0b5bd3c32821d59fb9	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\x8624a739bfce8501db7273eda0e354420da9b6eeee7db10303cbb7139747652282527e7d658e00ac7d5b378a4d4ab8511b2694af8bf826ba8f6ea865debf0706	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
4	\\xf5624da64a392d5278dd96940b5af88a86e9996242c7d4ccca0901deb8cb2a97	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\xd75d3da1bbbbe74a58f5be02991417636d28b1a75306053a7c9249583ae3b04eb3172fc549eca0a27d7762143c8639d7de5641ca7c2d2a480ab2665bde2e9303	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
5	\\xcfb6b107f3352e0f3354da3f71bb8a1173fa0e9df0f4ea8cd65ba49801eb2089	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\x5058b31f4ef76491aa3ac602b7fa51c2c42aa6afb9a8c0066d6a087b4aa7a70b0979656875c682b681d29aae44569d6a72536b8788aee06938b037fc13f79302	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
6	\\xec0bd9ad7b7adf4add283af4842c4634c2a85621a84b4772d801ebf54ce7cc8f	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\xa4d367ca7d323f1d8e5062f59c497c7c19d47048538bcbc1222f23e03dc06da8fc7c783e30c472f984d6f0fce2519e1d80d39baa13a4d8a51a6b262e2139460d	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
7	\\xc566a8eafb7c6ac4b1f7745d556ea5f76f5b2b6f6a9207771c91e41033733cb7	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\xe501569fac1f099871d6e15199d756504c98124ce655c39e86d32a5eeef9dd92bbca67f30a4b00588ff7656f5846dc068a53ce7ca4d190e8577e551d9531e10e	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
8	\\x18f628303d508b88400cdc1e5c412f78d26e809ef31d1ed32da97de31300360d	4	0	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\x753877b7af78c54f4d0a7d28c3a83bd02833c907473d77d0aa9120ca1b0a162ea5f18128f65b3ee899e88a4ae38b1e735cea2dd92429f407567c0709ab4eb308	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
9	\\x56ded3e3f874fca9064c620703a82a6224ed5519c5d773401477b28f2f5c075a	0	10000000	1577213582000000	1577214482000000	1577214482000000	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\xdc075e814fe8ab8fb2ddaf58ab4e6162b9a17603ffef09303e884cfa9495b95faadfbc3635b0217177f2e87df498fd01d2b69544e96e08be9792d77b9b5a42e6	\\x4ded37602cbe0de740eadc390cccf1e9909555cac4501b3349de35a351260d5f4d2ed5a401e1ad1723943c128cea93659c559be4ad1d93f67f9b887ed7cf4208	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"J2EYC1741DEM2AQ05MSZ9ZQV65Y9B3HQD1ABX2KT7168V0212D2SVG3XQ48PM6G5KM03BDKCS4AHY8YRWHDM90D6MHMKDCCCVD3P428"}	f	f
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
1	contenttypes	0001_initial	2019-12-24 19:52:57.936994+01
2	auth	0001_initial	2019-12-24 19:52:57.960975+01
3	app	0001_initial	2019-12-24 19:52:58.002133+01
4	contenttypes	0002_remove_content_type_name	2019-12-24 19:52:58.023652+01
5	auth	0002_alter_permission_name_max_length	2019-12-24 19:52:58.026658+01
6	auth	0003_alter_user_email_max_length	2019-12-24 19:52:58.032039+01
7	auth	0004_alter_user_username_opts	2019-12-24 19:52:58.038481+01
8	auth	0005_alter_user_last_login_null	2019-12-24 19:52:58.045071+01
9	auth	0006_require_contenttypes_0002	2019-12-24 19:52:58.046395+01
10	auth	0007_alter_validators_add_error_messages	2019-12-24 19:52:58.051581+01
11	auth	0008_alter_user_username_max_length	2019-12-24 19:52:58.059761+01
12	auth	0009_alter_user_last_name_max_length	2019-12-24 19:52:58.065526+01
13	auth	0010_alter_group_name_max_length	2019-12-24 19:52:58.075182+01
14	auth	0011_update_proxy_permissions	2019-12-24 19:52:58.081176+01
15	sessions	0001_initial	2019-12-24 19:52:58.085738+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x2f1eeddb11ba64ad64c981cca972727c39b7e2b989146ee7a92da9c9d22c42c8a7f0c960aa664684f46e76b64a0e31b2a1d5835455219d42b87aa126dcffbb0a
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xebdf0d6c0d77024712792991c1a0967ab747fdcae176d828114c3667c6bd9fc5f4608bc0e8f4d01aac0357d96c3b496729de8a5c18bbeb1ce3e4520439937c09
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x3a1ae44c4db87e10e0f8619d54025af507d7efc7b8dd93ab6e5d80bc2b03f73c5a99d51ad068ae84a33003390b7f2eb512b0ad6973483e8bad72df54955ea509
\\x750ace85dd62b0dd5f823022e2fb452ee265d1e71026666a438d85edaac455d8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xeff54a7f699a5caa4eeab6ebde11e84c48df823647c551dd0bfb3a66dda5f47d5410f7525c399fa3d6703149f34e8f5ac3b6f91003c13bfce91542aa756c580b
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x16f8cdf466b0b65d22a29f2f5284e4f33aacae08877fdccac8e799bd84f5ccbb	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xb2c0f7902fa59824b7b77607226072f7617886d5e4d3b2da8b8f1f26656ff60b6b1f9ec72187bb6adfa05db2c0b7bf5e4d62de5364d228ba7ea593f40ca40087b2577e54ac3e1df8118b603e522f9e2461ecd1d10581d1fec01f6b78701e651f7d064c916c2104468ab5e71133d0fae42edda521fec20c4d4bc793d393c061b0
\\xe992cfb026a8e9a16229755bcaf54f6e76a385bd8eabec0b5bd3c32821d59fb9	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x775f90e88f1e5f2eb447b28d30e57f420e233c016dfd4ba68d61bc11e563ab3f88ad0cb70378bb0dd420ba030ff2267f1a92311454d0893f7033f88911222a1940716adeabf6a3408a851efe92d75150cade98c0e35d7251160bb85e500f3b81c439241bcd5ad8d8ab3f7bd515e9854db3b7eec47fd05f6e7c81461d5af4e9d4
\\xe698a1275e6fcef870165ef9021e72134220873a7ca2d894cea4fe1e16f7cceb	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x2d68d78a5940b1d35d5999850115d15e7cfb1b8e9355476fe74748bc1190def4a5b8dde24e3f2bbfd1edc33d8af6582368649ed3d974ab247e9f0f99ea1bbaa0f891f6f228ced91b8f4a788f39897199d31541906ee7a2259c74d3dab3eb15d70b1bb37054d2203208c0c910ea19e435e8dbf838e2542c8ae5a163d512663e2b
\\xf5624da64a392d5278dd96940b5af88a86e9996242c7d4ccca0901deb8cb2a97	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x08fdcab6168add0c021c3b61134242e43dbb88ecc2d3efe1d012df57b0219b2c7eddd332721d53773211ff692c6283fdcb027c23b10d084019f58d552284af0b41f1dfe36f10ed853088313ab43e0b4459d1d95cb60b7d95f7841fd249195886d177f25671d9b74d110367b4457a1e34b342e454eedea60a2544887f79751405
\\xc566a8eafb7c6ac4b1f7745d556ea5f76f5b2b6f6a9207771c91e41033733cb7	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x2115ce491453c96b2ed03f103bfdc23d8bac096077e8eb4d85195abb9a6a746b1a4e7b3c715804bc39276898da6d665c3822f4dc1177953867ad5f009096ab144d240addda319b2cccc04d4648d70ec74e4e7cea3d2084a35ff8db46585af4b4bfe2923fd791a1d19d6ccbdb2aafe0a2704ae2040841968b0fd4cca8f3dc4eb6
\\xcfb6b107f3352e0f3354da3f71bb8a1173fa0e9df0f4ea8cd65ba49801eb2089	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xbaaa4bb4888b6f1ec2ffb507bdd92c03bceae80f532bfaf28bbab1ae603761c85d979b6dc1ab44806336fe992ec74b282d92fd57d64236fb5637bb93071436d8d607251dfe9ef6366f267ed1d005ff70f5161b729fd10fb46be72e43835209425d0594fe092f6011de173ddb4d592c91d40dac7cafef8b4a4543cacd7850de1b
\\xec0bd9ad7b7adf4add283af4842c4634c2a85621a84b4772d801ebf54ce7cc8f	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x404cdba535a3ddfda8c3966d4bfe5a8705cd4b3362a1b323d9e0ad0cf47008c2866677ac1fa6fa17320c7a1105f458e3f6ec7e3db257c3b971ffd2d056d55952d65701afb978e77335aeb966cb9440c4c2367af3e32e3d7c9bfd5affde00d71d32e8666f1c632d7515b1e1f11b1aa5f1777a3bdb192361ee62ca4f62a30d6015
\\x56ded3e3f874fca9064c620703a82a6224ed5519c5d773401477b28f2f5c075a	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x8c5f177ccc6244d83a7b6fd5473c8d389aa4b7ac77e920117300fc46d6acfbc957ba205c9b0b2d9ac79dd35c129deb335af8b7ba593b04300b137a6e1cd1f9486ade419f8b366e6d3143af5593c58ad2c97f004115bfe26addf753de8ea7e7f0f3936121f0516533f33af70664ac8b816ad435a0cdcc3612e94c799f8493dde7
\\x18f628303d508b88400cdc1e5c412f78d26e809ef31d1ed32da97de31300360d	\\xbf4cd487b491cf026772fc54df30424f552dd5c2966677c35fca940791d8b9385e4bc3ee676c969b57b85963b0d84618e605fd26fc1bb0683cc4066004213122	\\x3eb243912ed6c7fe3ef6d9018b6343111c1ad6f502885aea9dfa54b195794eb67746df7ba0035e6bef1ee25488ffc5dcbcd3f069f75ace22b9a47f6b4dc5124113d62a29f036e9c42383a56413d7b2cad13e53d808ac3c69accece5273a3922178d5a5b46203a371e3dbcc424eb9995485db814ed53caf98cccf6c7d3b0169c2
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.358-034DK914WHP54	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373231343438323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373231343438323030307d2c226f726465725f6964223a22323031392e3335382d303334444b3931345748503534222c2274696d657374616d70223a7b22745f6d73223a313537373231333538323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373239393938323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22454d3543583145584341524454515732363048453559543535564836424d463732304b3643544a33485032595641503441514330227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a225647334e5830414658324e525a4350584e584341504b4b3143415754325847335a5a51474a433159483136464e35344e513546544e5158573652545630384248455a5345475a464d4b335947334d4e504a4e32454a56473851544253354e56564b444434355347222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224143574b36544547474b415050373346344b5852303539344350504d4652423854364e395a4b4537323138593153535830435430222c226e6f6e6365223a2231545148324135365953454159335443574652445733435454585358444d3050484e383130374d4450395154524b443157464830227d	\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	1577213582000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x16f8cdf466b0b65d22a29f2f5284e4f33aacae08877fdccac8e799bd84f5ccbb	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a524a38354235454d4b4e41395639503044564b4a5351484254313357504e543930305354305233455234504139323144534132385357324d38505434334b4e37523844443235354d574a4158594d363739425142363856395441394d485a424d515857523052222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x56ded3e3f874fca9064c620703a82a6224ed5519c5d773401477b28f2f5c075a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224e365a585450454b515738473941484239344145354835563058573358335246355746485637334642325348593448393637463746514b354d3751584a4a4a4453544453374647574a3758534334374557574e4152454731524731303137365a5133314d343238222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xc566a8eafb7c6ac4b1f7745d556ea5f76f5b2b6f6a9207771c91e41033733cb7	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22585259323854573539565353413537344b564637475730504143343357423741543047313744314b445633443554343641413051474d5450375757575a385939353443425945384532535a39395137424747514a4b35564d444e3552434d574a4a433043343252222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xcfb6b107f3352e0f3354da3f71bb8a1173fa0e9df0f4ea8cd65ba49801eb2089	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223547383342434d5854324a46443743455a425a57453747315a4b33415134594e34513132524253475743545a4d3251474531445046324652454b51364e4a5a4248535835334632474e5153534e42305a4151595336444556534a56395044484a4b4b47434d3352222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xe698a1275e6fcef870165ef9021e72134220873a7ca2d894cea4fe1e16f7cceb	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2242424e51324a4a385958485154535a31305434464a36463446424d574d4a5a3438425936564a375831464258504d51534d42364b38333536305a3332514853324e32475630484e37304154524135343647423630454a4b3332475a374b4d4b4132465231503047222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xe992cfb026a8e9a16229755bcaf54f6e76a385bd8eabec0b5bd3c32821d59fb9	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225457414658565645353954334e5a533446485032324a4738525a365452334138543657415048475347334e474842434b594e534e575137583036314b314745394a5a59444e5152544b315a4334453356384734374d5830564d4856594d39523738473741503147222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xec0bd9ad7b7adf4add283af4842c4634c2a85621a84b4772d801ebf54ce7cc8f	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2241484a585a5851505647444d42455454483050595446483248415944535332385a394654523135345853485438344341583052504254473035355743364b4b3136385033514a4b57395a314b5130424d345a3842505234565453344e5946384e47533951573152222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\xf5624da64a392d5278dd96940b5af88a86e9996242c7d4ccca0901deb8cb2a97	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2258545630354b465639584a434332574734483843344a565656484a4541534b3958544b56324a4a435944535231365a413242524e384d433136564642594a3857444e5248455051345759524652434d4b44453230384e563931393650305931484453485a473030222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\\x56164e9ad5d65acb7fed2a0e4f0c5764eb0b1a53988a6fe88d92200cb87bd05fb88ec34089b4b96918866a7f66141406d09e7581738acf642970f602cd17c4eb	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x18f628303d508b88400cdc1e5c412f78d26e809ef31d1ed32da97de31300360d	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	\\x73d0eecb4b701909f8fd9daa6156b4cb652c56601b97fdb719362fbdf0b55604	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22564247334836454e4b435a56343257334736394e47334833384a4b345746455045333750514558503342354b4d57383642444b34394b354335454b5945315932344b37335339563147504d345948565751314b535a37505051414a38335a513233314458473247222c22707562223a2245463845584a5442453043474b5937584b504e36324e4e4d53444a4a524e4b303345425a56445253365251565657354e41523230227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.358-034DK914WHP54	\\x53393369d084d56b1c6f24fb80152465ad47e168d1aa9fcdc71051e0e73d0334	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373231343438323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373231343438323030307d2c226f726465725f6964223a22323031392e3335382d303334444b3931345748503534222c2274696d657374616d70223a7b22745f6d73223a313537373231333538323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373239393938323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22454d3543583145584341524454515732363048453559543535564836424d463732304b3643544a33485032595641503441514330227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a225647334e5830414658324e525a4350584e584341504b4b3143415754325847335a5a51474a433159483136464e35344e513546544e5158573652545630384248455a5345475a464d4b335947334d4e504a4e32454a56473851544253354e56564b444434355347222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224143574b36544547474b415050373346344b5852303539344350504d4652423854364e395a4b4537323138593153535830435430227d	1577213582000000
\.


--
-- Data for Name: merchant_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_proofs (exchange_url, wtid, execution_time, signkey_pub, proof) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (rtransaction_id, merchant_pub, h_contract_terms, coin_pub, reason, refund_amount_val, refund_amount_frac, refund_fee_val, refund_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_session_info; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_session_info (session_id, fulfillment_url, order_id, merchant_pub, "timestamp") FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (tip_id, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_credits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_credits (reserve_priv, credit_uuid, "timestamp", amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_priv, expiration, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (reserve_priv, tip_id, exchange_url, justification, extra, "timestamp", amount_val, amount_frac, left_val, left_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (h_contract_terms, coin_pub, wtid) FROM stdin;
\.


--
-- Data for Name: payback; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback (payback_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: payback_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback_refresh (payback_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	\\x18f628303d508b88400cdc1e5c412f78d26e809ef31d1ed32da97de31300360d	\\x9fd7667953c9a701f0da3b0c055a3847ef3d8bf84cccf654baf6fb2cdbeb1299c8c94ecba872693d9747b3953c9140445b95d765a01214ce1a3dd66da5bf520b	4	0	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	0	\\xd5900155286d4400c13e79ad89fe18ba6c54b2a6821b562521ff20ca17d50e71d1d1fb458ac76bd7321b0c8915d28facf0883691293017e98875879f6381de07	\\xede669dfa22144c16fc370fb9b3230567d597491f7f2c6d3e789967943f7f967196181b9c2c905f53340b6c04d464b1a7294c88c445ae494769ed8a42844a847	\\x701a9353d137150ee8b7227f84249554f728b6528ef70efd61d91e761efc250dd72cfcfd71bbc1634ffe96acbc69ce8859dfa0356e630bd7f01c8c7765d807db17b6ecd22bb6be5cea019dbd99f3dc8d001a1ffa4fc17fd2dc91aca90da06707de22d9839de065db8fdf2020742d691074fb1b8b967c2d7200921ef33ffc7f1b	\\x48a9e746f7e0d2df899bc5d55301424e1a1c057131bd1ea45cb57268d140ba352a0177935565e48a817d496182c08708f9d77f34b897ed9be3936bf1e5539f72	\\x0417dfaebc9cfe722021c2d16837551677fe24c3adfb84c298f5af91b3a0557f21010ed3e79bdf0dfa41e4213777b5966925330f7b20a422b6986d281082f9302449a9260f4bee84e161b92c4a1ede4bddb6cc7739742d43fb716dd949de35ce8ca2e962d2953ecbedb3566c5604521bd269a48399f5ebae9df2cf88d0801ad2
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	1	\\x369f5dbf30881fadd9aa037a54767e9b8bc48824978fccf93af0e621c7182668d2e9b69de20e75a8e7ca484ac6d50a54864e40f175c987d88d4558adfa68c60f	\\xb31d4c665d78d512f1da0b98da0ef511dea23c9399ab2e30fe57ac47f37703f61958f212a52cc8496cc8002baaca763f5e4aa5e8ce5c6d8818da787aea15904c	\\x9422af9c72e991b20cc81156ff71653c706968c0f29bb222db42bf57e77a71ebd35bd25222876dd36f1557ff733dacd14550897ac31490a8b632056e932f7309fe5e8fc95c8d7190e7b33d2b1b4dbbe1d64af564ec4becb7b131c18c78d2434bf1638f34ae11fb6f8b034d410230ff932ad9bec570451342781a32eeac09a495	\\xc273193aa0708d55403d5f9ed0b5148b68634b4b2c9e6e30581013302cf504a1bd138c10efddb822caa3ea198bec5b4cf321482f0f980589608b1c3dd246c508	\\x1f027eefa8deb3f6ba8d90522c01d5272904a89d1f584bf70a314d00a3b9a2d9a64724f88dbd44947261458986ab0ae1914fded6de0b1f0b5962d2c87d3f2d7fa6b7f310c2d69ed11963575245c9e518ab5b5aae5ad956f34b65fc7a29b3e279904f5ae20c0e3d949b2535e3da73eb0f9d1538e7884410f5c0d018fbb5aef401
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	2	\\x8f7211e46590b65c504e8acf9081224462dffa19d13ca3c53d359573ecf37e1f7ae9f2b5dae260bfb209e50da9b7213ba7515485a42a40e212a731e7f93ec202	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x90a128075019cb1d93fa0a458285f8f4854915cb23c5300416668af8706f29f95738c2a603ad8911f767122f172c4cca4552a159e59d2f9d99e995aeb678c05fb1c5de17ff794d3c44a7fdaea3f6b9563021413baf1dead58808dbcd2e0779489f9b158923465e752ae7d43c84b0192cd6ebb588a40241bff00fa3a002bbd946	\\x57760c49f63acf31bb186073ec286e424e9751cbcca2b72244198e0a24549f79193962373dcb5d558e727193b2473a6b973909f338228474cce135314057a1d0	\\xc54fc40a334f08c89c4a29126dcc3f449cb390c5ee70364bef3066a29cbb679dc97868a5a504957ae35d7b3db31d041b153a0956b780a884a914af48167754ffdecb4dbf10e2f828ea3d4762a634a5ec0fb3f6fe81d0eb991df2ddaf9c1758105e9ab8c7dea2bf7f5e95ca27059e8c104a45c38c55f065181e48b11cbf5d9f56
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	3	\\xb1459150babb3ae5b6932f0f2b683d23c6fce5b28f2eddb59ea4b719a8ab1cec2169f292782a0466c01834fdd5d3f0db9c1b309dbbc8a720dccc15f777285e03	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x2ce44ba83de0f9be186adfb8606a4600a50c34736d334441f15f53cbd339d145831c47866307470822b95df884c2589f1636bf9af9cd6d7c5d100bc1992d0e52d679ce0007fb1fc11c96d8f54a5a5747a9ca8a1b8a46d3ed94a12f2200c79ca3dedf0d205c1da9faa55a53745fec1712c7c67b35552b7d553d5e8eed02f1b0a7	\\x1e70d289a920b60ce7d908b0528c70d1839fe1bc1a3cbc9663ea944e8abbe93c956e8b891ca35538d8e3d4d9fe47684fdea6d22c68845dfc6a8dfd29dcb810ac	\\x50c44b0d6bc22b337c171c5bba81cfbd6fe4854d3bedcf5a9d9e35fb1af41e7600fe215ef8a3cda11f8137708780fb05dd04fc3e53c33866884a4cea65b2b946c93d05822680a576392c0d2da14e7ccd5cba1cd39aca5c3586aa9913bd9ebd2044ffb24319129bc821dae3e879e53219df1126a8040bc41e11de16d4534a21d0
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	4	\\x9f63280fdfa8e56255af6750f9b42c9e7189a64d56ad4c25c78a37e9a171e9d3ecda721d77b045f80ea86b4bcced50efe9059387b6584f38f02274f5d5ccb005	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xab49e6f5c4876eebc94325cb76b9e5b96f6969a02346abca235a74c102c592c4c832feb006f25e860a844693b5dfb84c26152c5aee6a77c62aa924c1e433e64d8e720365115906986092048e72ce099c63c49bf58ae84c62be50647760b80689efdbd351ead674670035374b34abb5ddc89a175ec10b9d8ef755582f9b3c99af	\\xc0836ee8794925d8542eb2c433d07a182abeafa61146c16400028e3e6192fd08cca70553ab1ac7d1a2b59c2351a9036a1eb35550d2fbd3599dcb4bcbc0916e9c	\\x53a82a786f10d62f44449f3fdce879ecea6e075093c5ef5b72e969ce0142f561468083a9c0f06f71bba653c28204d2dac6ee8f21195e008a49e5005361a63c3e771d8acbc7935a7645306fab8640385c94f4da12a00628024fdf52bfc2047ec801b5ae61fda3d54ae69193121ea91a9450c79684ca0d1b3ec9a65c91b92fc1ec
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	5	\\x89221791e6fbf9c3c1a39a7999bc767a08783835fd727e4da26e44c5414c5a681331e55d4bb62346c35752d01c91947b9670e19a8f5239c29c665e5f56863408	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x3f6bfd9a9ea8c74ed87b48871532e250fb871734f5c207aaac2e6d9292bcc9775bebe4892cde6fc24ed367d1b41d7d25de058f8831d664ebff3d91ca9efa4122e41d77a27613a0e153bd92df243096091e5967fb49691d25d6290fcca8520727cad00ff068d4334c112d0b24876f97fa46026d7571f6bf9bffb8b6cb5a635510	\\x509d42c6d9a7b52acb3bda2b816020d873d9c11a444764151ef0f305390511dc717b306edbd0a81c741aa8f322ce9730ffbb1d2d1f0338cdf29304a2a2b9818a	\\xa7369437130d778eec372e335c0506e944a87152d246ed4c50f7699dce97e544f1bbc5a25beac0489aa196573925e481107b6e3a8bd14b6af7ea7dca6a1d29ff7bd770a9f2c381adcfe40b068a75a19b330c94c9f623e462ba3fdeeb40b6b842b67c815264bcbfeac2f83855d36a5d418a5e8e7ce8b6311e9654eb1f023e1939
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	6	\\x0eb0956f60a374fdef8fe9f4e22abb420c79bc396d470f1d13aa6aa23039d43ee1b1e075e0c852402303edb6f9776d0fc124b50ae467bbb3d4dd8fab965cca0b	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x8a62b8cf4290f9c5bc6488756c50028b82cf4b4cb09877e32fbfe63c38015b85f90d7faa835653feeba3990177ab8301b73b26fed423eb144850b9f1f9374c2fd5aba07b89b9fe6c4ad96afb57e7f36554e601a8bbb7246c647d60eedef3de176258dc983c4ac2339155f700c6cf2d9f2c43fe8249bb8336a55776429bce56bc	\\x9fe39dcb8289c894829882c40931778685cdddf80b31a2bd6c60d36b53e00f5403b74310d6ad8f5b4b888d5f6533ce3011378a9df50db900e3b6538af7ed453d	\\x3f64bb8fe8858b3b63a603967d31c5e28f77b761b5eda7c41452f8b7433c1fc9e96d61c8cfb4c29304958500d93578b5b371f57b1446ddd1cf75fdc151e7ea0993980958450ca1a2933f9a2de71b2ab923abbf87d0f04203c61a53b64db94141b62a96a8cea7a86b36ef6badf19ddec074e17b2bfaee4ef57353bdd1517f2bd8
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	7	\\xbae008ebc40580378d901b758b6cd0e66fdf4a4569bc38e64d0c20ccddae16b21786681d43dbbe25fec88fb88761c37e5b438790ef3800b8ca4eda7d3cee3c0c	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x4d86043c8ae5df5ccdadc80ff718825e9eaaf5a1cc1791b9b80813d6e50689de4f312a8b2a3642c9a352eed119df7c25ef5cb78c71359aafa4521d24e4cb052d7dd9281b71b71fd515d8745795d225d7d2fb94d7f65fbf9223a7b504ae01ffad8d4e1d4cde9ad5d8b2d7d949f5028285cee5964f40f11f36f776b601883d1051	\\xe2a0c6936c6ff6d48c50adf81aed72e0285c7b2ac1db039a05abf2315f1312f44273873271eae03035a60e1e993be410ee3de394bcbfbd3409e1e683afba29f9	\\xeb26364bfbdbaadc021873695180a1a24a12520a399bca9d97c493a1204d9a8c189bff19533d34073a0a8f58bead2f102459bfa34ab0a70ee1302be9cddaf424171578a7b328a0ba58fc79f9c2f5a7a79ce5c283bbb60679b48cd398443721425b699676b8e43d330b1a40b77873531d0997d9805f1298f3a0f7948606528288
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	8	\\xc69ebc2b3cb46359c2d40d1453c807be7585c47d6c329e64ac269552411284431b4d878e687c7985da90f735b65e4279902ff729c2c08b83ee4ad8460d0b6702	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xf1fbfbf75e5037456146d6cfca8d04aee1860050e5aba9c451989770c191e3d8e4a1bc0d63a6e7b660167d3dd4177db002745012272816bd8e58eb0d3ff9439e6c6cf2e75f27cc9153ff2e1571a39943489aab0b18c7bb472f5701e7e2064c10de36378b44a4011817aeeb9c33451c3b44f66502b020aaec11b24150b7b34f78	\\x21f74a188b77ea323a958bf397c018720c4a78708651434cad2ca086d7b06cda05030d5b9d0b2366b56d55a59bcd73f0c941672986488ca519beb80d62c19b5f	\\x2957d0490c92a2eb37b2194ae7abe552102095eff15a6b7ede5f308cead2dede3228c080cab84fbaabbfca90254f91d0e0abb4d1a8072e309fd6a6b09818cb1743d0824fd08ac4006d15a917cfda08693b9af40310bfe1aa7f29a7123d89606518de8cb2ab2e85269db2c2510df45a7855a823f1ed6a08aaa77bffa3587f26ff
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	9	\\x1c77e5f0c9aa910b8afecc7b7f4c81e21aa66f3be2f739f72da5ab318807ec69ffcd7e53c3bf0fafa8000af2113e8db8b62aafd3491d7659588914b92cb69b07	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xde0cc12cdd907222d50c8d15dfb42d2b392ae0dacbbb9f975dcd2471f84181047041b7bd6aa9445814b8ab5c8dee5e36c87b00aace17ea11da7ba11cf62f6508e60ac584230a7470767e4f521600386f6b45485144c3a61148474d4b281ef544f8eda50bc2b36922f5311d98c37bc5a20e8f1db04c7b36c57d0a786d256d0640	\\xd10f7b04af432fb8bb8015f56c16a3805fd8da17a54f4659a2a720ccd9c1861b24a0aeacd5c443745b668801fbb6462acf4ff691427b74beaae7db4e093ae998	\\xdaf1021461fe159f876f5ff2c29bd069c66061a3f33d79993587f75554c92a1be3ba977cac46b21a9331857250ea3c973a48035c9b7886c65385490b90646dc3483a04807b67c7bff67d223d0105622ae59999c56056e6b4f113179625c372277629ce539906d521db941b95332b456c4b56eaa716835e849bb72e4025e83cb5
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	10	\\xa07519d2a05f6cede6a4711a3465abf53c03f921c018a9fc86d82b8a3bb492d5904f1fe03af8be5c8843ec8b2171306104417612888505b85bc420b0460fd50d	\\xc195261ead0cb68de5283320700a6f1c0c4d653a8ae7f8dbe0846a6b2c702f3e4fbf2b06d153de65b2cc955f882536a1d1ef126f456e24b5e97a99ca3d34201a	\\x331bdac65cad9d467b2d21548bb26590571db00ac4f8f86efae41380aa1ba570593f7b93ed807a5759fae760fa0a27b831cfe430a4d742c15f398d8ea26b3a65d7adcc0bafebae00c61b2b2e816af113f924bcea2fe7fb87b3fc099763cf41431206d2868b701e45a7253a31cc32c94f8efb7e90f6da9fc33a3eb5d84a98511a	\\x14510af6ad463a0d4850f86a1b44c023667bb7f2a1c53ad858186e74afb45983e1fbb45c69ac25196a63ef114fd517fa3d912962692141e5c4c88077c18f09b9	\\x9d1af54b8e5e5132cb0e949e26f96cc547f233568010381c67c77aae2f6f0f4466245a7003d5495deaa501cb96e5415ded6c02f2ca9adb2a3f7840659f0e8ea2bf6b939ab5b388fb2851c6cf22eb9440af7a603cdc7de0439ed1940b74675eeb2e337da2b05b94475951830e24cb2b91a856305cec619652ba57f8a87ed6f942
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	11	\\x36272935a899269b85e2e18a1616527e2028e951b7235fcfd81b2093cb8305180e506ad6185a812e0bd2b5d4b36ee15759045f02d08a6ca9cd3095a548d8f505	\\xc195261ead0cb68de5283320700a6f1c0c4d653a8ae7f8dbe0846a6b2c702f3e4fbf2b06d153de65b2cc955f882536a1d1ef126f456e24b5e97a99ca3d34201a	\\x8116de53c87fbef4bdf1c5d2901903eab4e3802e251aa59267d0962520cf47057dd36b41e371fc2db22e69a95a40598cb66bc7768f803ad4637ce1b38b2306921101c73462cee3de13668f7a1220f443bba2c440ddfaa4eee70a48fe40a3e07890c2ecc8e4f486c448b6248cc3e74ff2b2ee694ed4dac1df7a4c54ae833ea996	\\x0db08102d9c9a902c73b8393fd7ab01edb7741048b3f8163808081dc5d7e4a9e1ea71ec0f7aa13a7e40ca04edc30bdefef85eea408c81c16cef192fa3307cacd	\\x4008c6dbbf92a27c25ac965d87a59ca325bfe450295201d895dd33d71247d47b2f393baab6eca9fb05ec14a11dc86c1f0e3ef17579accdf59a79a3474ac689e3dd7ee8997594c1001bcca25281b30395f74021687256c9a269d196516b6c70128c52062f646d2452c33fb3cc19ac5a9776c96929631421ce67fe83c0d1d4f402
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xe08a72766aa54f148dd5fba19e16f15f51ce009a3af3c8ae74849fc1dd1c9505ad0e0cf825eea87895588870fb20aed96cde499d41e418b589df018bee2b4456	\\x80b5791af45714ae9b2cd6c21c139560386c40243537d08ecd61cfe688f73478	\\xb97ff5a2d547ab01c78216a87f5c76e66bb881ac6b2fc38fd9aed7e97218862f607c9a2d777f0fe81adadac608bd23b2327ed024b0b98019c99177ba460b4acb
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
\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	payto://x-taler-bank/localhost:8082/9	0	1000000	1579632781000000	1797965582000000
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
1	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\x0000000000000002	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1577213581000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x505ac0deece8331a4f584637371ab5f71d909e3ce7687b392248b1ad1f59f65923c45db710c5748efbeec44dcb00175295553d2b505c14cd67b75ba0e61a7767	\\xbf4cd487b491cf026772fc54df30424f552dd5c2966677c35fca940791d8b9385e4bc3ee676c969b57b85963b0d84618e605fd26fc1bb0683cc4066004213122	\\x69f2ed249ce80d2f4780379c044379aea9ac88ddfa381e070cbfcad928df65b0ffe689c068afdcf7b5b093bfd14cf2478f58005fdbed64988eeafa5079ef5a776647a9af49a6026f3e791ff0040c87735b759b1629de80d2bf54bf7336564e656b4539b592092ad5218f6b07282d63f7a8684ec5d7163f5426879861c9531741	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\xc122de57d480f58effee0c4b1c6d0e50bb28e0f352d6e509b3086c6bab5efce1d54501e30d50f0bcb16091f2bfb87832c80ac76452ee871e9478603f02e9d90f	1577213582000000	8	5000000
2	\\x356287daca5179e9aab1c84cd390242b9119c13cc3def841d81a8f71abb44003c2d5e7dadc33ba26a45b615fd4bb36841f5b36cbc511239ccef5dfcc988d6289	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x5a2dd5c31a3e68f44e8d34abd668cbf4986d180798ad69964c5eed523eb907eea424a9d1e52d93e5e382769ff229d09a5f70abb9648842e7254198f93c9d0a11f3c97afb7e87153e5457339aa20b3b5c89a1b0aef3407282670f7f4fd42b5f6b25f40e903ded0761c6afacfbf62974cb213ddba9053067ccba3e00e60142d2ef	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\x36d5915b2ce8b87f4e55b95fc514cdb98c5bff0d01b79662efa621331ec13f5c6843e579513952fa036e901db856a6f4c3b3ba913064d0c29e883ab9418bc70c	1577213582000000	0	11000000
3	\\xffe13dccac3c9b73c8415247964140a29f351046e904f2dccb842632e60b7f913dcc28897466f0637fdc8170145ef6354c954abe7d5321cd00f304fe605e4275	\\xc195261ead0cb68de5283320700a6f1c0c4d653a8ae7f8dbe0846a6b2c702f3e4fbf2b06d153de65b2cc955f882536a1d1ef126f456e24b5e97a99ca3d34201a	\\x48019a5d3840556850815cc9a67fb4b1af96cd22e23f19dadc287f41768af156f68adff8e4929169c1c0d7077feff8d876c8f0320721feb8fd4ee7222a3776fdfead9527797d9b3318874cc9c89dae74c994d416e704a71c3f6ea76305f97cf846c68ab32770bf656ffb80ffabda3d18fe95db614e458d8a631e79b0348836ab	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\xe5abeea795cd3a35d300f5d2a4d61622c49e566cf724cd4d54def7353431dc8ec69265e19418db99684fa4d342fd624ba16b6e62a1258f558a79eadf29be8804	1577213582000000	0	2000000
4	\\xf227cb9dc9ec623ad3940f7473e92617bba4bbb7ad297e092ad3931c6514de4c6abde05957cd8c609d9c2cb666e3a9db1134301fdcf564be1586c823a564e56b	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x128fd1ae4409b9a0fb867c0fcd65a05d4392b120156822fcaff76d1976255be144ca1e03e6bdea34e31c0ba026f95ad7cff8dfb844400e64555741ac7c459584b3db013cedcdf73455fef7ddaa19c95d9347f354610392cb7f89d703c49556c9441b4067f8c3c8e5e8501930c1b620f2a7967dff991f8b4cb3c03f3ffcca037a	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\x16f4a6880ed0c418e025629b0c802f0c60759a0e8907f066728a59300e7fc2d08d9e47d153f277922cecc56c9f1e08c9c65826ed05dda287f0b4c31f6cd9630e	1577213582000000	0	11000000
5	\\x3cc01dd6861107fa40154b1d8306e391ae6c9e0f4ee1118bcd31029d67d3cf12921ca364059750c3cd9a98c9fe8c8be82111db769067941c18e2dff9600c574b	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xaff7e2aec831a80eab13dc2f9dda5f394c0c421864407666cde832e5a6b9c1e47c8a8f9aa62cb12f679581650e57c02386bda5b2b483c1dbf915f8aaba0e5e7279a592edf21174d9744386ded7ce3fabab176561ba9d65d089a603396c5ba6adbbb9c7fbbd644381573bd739c0ccbf7db7e2a4eb1d8786e71277583374529214	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\xd103471fdde12e01cbcc57914d947aa57a628cdf3d1ba32f717a17451091097d6d05d4fddc51c379447370aed76721c7bcc45507d7b3f791ab4ad25476778802	1577213582000000	0	11000000
6	\\xeb14c8c06ee47050aababb5d130a67363f656a863e38afe2c6f51aed9dd4c903e8b335c67bd689cc102133bd993adee54ca005c31b6dc64c3e7b2150b389457e	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xa0c8cefd7176216c18ecae516793d2165fcd662db6bad5d1181ed6bb88b549dc26b18d35cc399dc80f29e90d56609143943605881d6bfbe84d8a1cd19816b8fed7ee4c7da9f0821586252070beaa7f8425f72ba089c1cec195d7849de35d1a31ad96e6bfb4a562c4a5bf28e41786f53ac9887ece026870cc502e78f32c830d53	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\xcb5006159c19365377a530276b0735c81aee28cec5bf0184b7a10441627933b77ed003576131d435632b2df22bb71e7a4743b969c0354135122556e1b1170706	1577213582000000	0	11000000
7	\\xc3418feb781234a1dcc7a0e7152c5ef74407ca64965cfb649696f3ca9f3aad3c59d1374f6df4c8d689580a81df60e61187391c5d5aa5fc8b711b0a8a092ea6ab	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x7250e7526fdebf36129e5bd60551e9aade8dd4f8ce7c657b58c6bf95d687a5d73ae8100cfd8891371b30f440959009fa3786a3436f651a8b04f497e0e0da2614e1beae76ab540d9c98a5e022f34b532244dba1a169f9e47d810bceb23fab3f198cea5d7457adf7f9362c7f198a2410dfc70a2643981cabec27181a13c0a0118e	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\x6adf642e60d74c53b5d0bd1754dc75faa7ca337a4e7d17e1a3e9abba18bc12e7de50bcbbf6908609c3d9e5ec8c608999e110438b3e1067af69a0c40390e41209	1577213582000000	0	11000000
8	\\xba79b5da6ad56e8355dd61d5b23b34e3e50ce2e68ad703d23e0f585af75d6d8f1b347c87f128400365aa6fe0b075087656f33942c1314490322ced95acb35653	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x67a0100cf7c4048fa95fb66d3b524ebdf0847fb32467f47925c2695323741521b204c53a31de439a30405b393faa4667b524005f348baf044e53ad015e097f2b3f7b56d6266d7159a58452f6e01b341cd5771d9e7d9d576c3afd06adec50921d9f49ad716797784316296ac811484e0ecc861355354648b1dd2f6dfb73533096	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\xc825d1742a70e54ad8d95d65a5e78e44a61d701b9c5f98be7519fddc548c66c5a22b3024cbf3a36aa3d436862630c3440b19426fcb1c7ac4d628b4fc4262c609	1577213582000000	0	11000000
9	\\x872c0cdf64891b32c466ec36b1073eee11d29c184f78b7c54c6615ee88690c3e9aba2c7539698dd11fa79bdb359c118600e2163a1565b7717c0f5972df1e35f1	\\xc195261ead0cb68de5283320700a6f1c0c4d653a8ae7f8dbe0846a6b2c702f3e4fbf2b06d153de65b2cc955f882536a1d1ef126f456e24b5e97a99ca3d34201a	\\x6eb4266ebb890c0bb087e8db27781091a6a3942f31692b5a816c9ce24e3b565abec95a42e13b11d8e688cfda90d02088de03d2c6256b00e6b322fe97dd269b9878170512e1f2634404fd323250aac4aed0b46b87442330a8fd93cb4719fed6c95a7f01fecce3398abf4b32ba4a36d46fdc5f470b60367dfcc42890335735a1ad	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\xde33594a52921d4ad6650527310d40be07bac483f05875e7490f33cd9fcfe692d2c182e922e999f3c9808be966ad5d0faef207726a9572f3c01818176482ce0f	1577213582000000	0	2000000
10	\\x58a3b5e083cbfa476cd36cfd2243612adae2bdafb2792ecedd6a88c040509e1d257b91ddb26addab87278b0e80f2317edd8b69af2db402e8731f02b293eb4e33	\\xb31d4c665d78d512f1da0b98da0ef511dea23c9399ab2e30fe57ac47f37703f61958f212a52cc8496cc8002baaca763f5e4aa5e8ce5c6d8818da787aea15904c	\\x7e1f79239242967312be8f69a696919950e112ff36f05b50b8a34144743a5da691e518d949db12eef8e12ba385d8311ae0baffe3b50fe9100cab073edbebc02bb9f89dac864da49f7aa849ce8f5a1b2b14c202f38a752965f82394c3a4f317f0debb35d216dbb70ddc134dc4a520d545c01d8c9cb4a4bce5f2323c9b4a0c61fc	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\x0b935104ad1932953630a78a4880ba72b11ac0cd8260a5fafc4662c7bcb3f04fd8b97a7232073e3029f58b64c22fa137ae4253b5a1723ef83fb62f4caaeb1802	1577213582000000	1	2000000
11	\\x5901116afa5f1f25b35348da7fc66e9798934aab3c1b0266119d57297f695439f552ae69704e134e0fa6991c1f424e6933e5e87cb9190a29cee80b4ae59cc4f8	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\x2d515debd8ce2baf183270189a10e48da9c7a42fa574137035d49814a8e707f5506b9f6fa5d061cd6a17a1f371e1e076c54ccb4070b5c18dbc52f377033f8ef95871f0f051c556f289213b4fb32af8b2395ce82398c142ed3062e0cb670c3adbd147c9debaa0ecf1be7189504c61f51fcedf208bcd73f3d58ea28dba03abcf21	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\x128bad4d1c882167d31dab12c1329ec1ff3212e3ff4a7f1863e1ec054483080895d62d87b71a3cb7931418f25cb6ba488ca1056626a551d469d7fd9cadf67503	1577213582000000	0	11000000
12	\\xe6d83e962242a7fa66fb946a342a5853270adfc18048b0308d78590d1b87f1164e539fb36cf11f714b2a3cd65a7aa44cfdeb14d6369d5e368e0bab3f1c420456	\\x3f791c363a5d6e19bb215633415bb13fd25891afa6294d51026233eda6eb05648aa90522990acd39507e55739935b38cd56baf031ce0fb59221d12e4f2e94d9d	\\xec4b856ef2c2263bf64959a54ee29651252d58f3cb3180cfd1b30aed6f478c00bb3791dc1401aed40a03edb364d5011ef72cb7a38bfdfe9fdd5aecee80f85f7ccb4c3156c4563a3e6d148aee02f0e33e9205ab63ae70b6d111294e43eac608da61819357184dbe18cc8aa792f9c33902233b4cb5d81c31ce0a009d968e1ca7c5	\\xf95b883eb2eb4f8dda0a964fd99d7cabfda6b3a5140f3edef18a4e7ca7c911dd	\\x10520163f824621e0baf9f9311ddad0209baa3e19489564d9855aa4afd2b349a1cf538a2ac683cbb22e40655ca02569034399751631605731e9ca3f33743880e	1577213582000000	0	11000000
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

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 9, true);


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

SELECT pg_catalog.setval('public.auth_user_id_seq', 9, true);


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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 9, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 9, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 8, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 15, true);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 1, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, false);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_payback_uuid_seq', 1, false);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_refresh_payback_refresh_uuid_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 12, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


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
-- Name: app_talerwithdrawoperation app_talerwithdrawoperation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawoperation_pkey PRIMARY KEY (withdraw_id);


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
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


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
-- Name: exchange_wire_fees exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_wire_fees
    ADD CONSTRAINT exchange_wire_fees_pkey PRIMARY KEY (exchange_pub, h_wire_method, start_date, end_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_h_contract_terms_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_h_contract_terms_merchant_pub_key UNIQUE (h_contract_terms, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_row_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_row_id_key UNIQUE (row_id);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_proofs merchant_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_proofs
    ADD CONSTRAINT merchant_proofs_pkey PRIMARY KEY (wtid, exchange_url);


--
-- Name: merchant_refunds merchant_refunds_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_rtransaction_id_key UNIQUE (rtransaction_id);


--
-- Name: merchant_session_info merchant_session_info_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_pkey PRIMARY KEY (session_id, fulfillment_url, merchant_pub);


--
-- Name: merchant_session_info merchant_session_info_session_id_fulfillment_url_order_id_m_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_session_id_fulfillment_url_order_id_m_key UNIQUE (session_id, fulfillment_url, order_id, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_id);


--
-- Name: merchant_tip_reserve_credits merchant_tip_reserve_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_credits
    ADD CONSTRAINT merchant_tip_reserve_credits_pkey PRIMARY KEY (credit_uuid);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_priv);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_id);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: payback payback_payback_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_payback_uuid_key UNIQUE (payback_uuid);


--
-- Name: payback_refresh payback_refresh_payback_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_payback_refresh_uuid_key UNIQUE (payback_refresh_uuid);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


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
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, newcoin_index);


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
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_iterate_matching ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: history_ledger_by_master_pub_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX history_ledger_by_master_pub_and_time ON public.auditor_historic_ledger USING btree (master_pub, "timestamp");


--
-- Name: known_coins_by_denomination; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denom_pub_hash);


--
-- Name: merchant_transfers_by_coin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_coin ON public.merchant_transfers USING btree (h_contract_terms, coin_pub);


--
-- Name: merchant_transfers_by_wtid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_wtid ON public.merchant_transfers USING btree (wtid);


--
-- Name: payback_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_coin_index ON public.payback USING btree (coin_pub);


--
-- Name: payback_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_h_blind_ev ON public.payback USING btree (h_blind_ev);


--
-- Name: payback_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_coin_index ON public.payback_refresh USING btree (coin_pub);


--
-- Name: payback_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_h_blind_ev ON public.payback_refresh USING btree (h_blind_ev);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


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
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: reserves_in_exchange_account_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_exchange_account_serial ON public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_execution_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_execution_index ON public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_reserve_pub ON public.reserves_in USING btree (reserve_pub);


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
-- Name: reserves_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_reserve_pub_index ON public.reserves USING btree (reserve_pub);


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
-- Name: auditor_historic_ledger master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_ledger
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_h_contract_terms_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_id_fkey FOREIGN KEY (tip_id) REFERENCES public.merchant_tips(tip_id) ON DELETE CASCADE;


--
-- Name: payback payback_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback payback_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: payback_refresh payback_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback_refresh payback_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


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
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

