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
1	TESTKUDOS:100.00	Joining bonus	2019-10-06 14:15:43.645538+02	f	9	1
2	TESTKUDOS:10.00	26TQBSW3G2YKBB9AH3DGQDYBSZVYDY4H3E7RFG8593AXVCDXDZN0	2019-10-06 14:15:43.728367+02	f	2	9
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
\\x6f9bba13975c8904a8c9882d4860a3762016835d096fe2845ee8a4bcba10d1a8698198e5a949141216ffdf007d24db3824c987f176e98c7479de970a146cb3c2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3073e10f602b828b4f66190244891f669866cc59c7e90566b3ca4eacaa962105ac293987aaa8df89ef35400c6e5ca1473160b0e093e57f5d53763c7fe8d7326	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9ef88baac495ea7337b8f6893a1f57083f0dbc6d904321bf1bc76f7134cea9c8601bbb539ca9d94e1ee8ed41ae73222b2913f90a14a10385d90e36704a1c038	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ea56c0d374ef55c3c654d10099ad40d04423659499c51fc684881b66bc3644b2c8dcb59f74d8793ff380670a69d38903f8018030d66df2a974fb49d03e88235	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8142382f4cc72d2e270c8932da8fadc8de72a4b6ee949bca2f52aa2dd0e329df64b664d56755e148b583be71828808a4095282053afa53c7205819fd9f72711b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b05e27ffd7351d3f62d2ab0d68b86688a3ae469a98e9697ce7e4af62c0dbaba900c78c4b038d5b4ef034ff163ab4d28f5436f3e20c46ca7427976097fef83c2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d5aa33f04c199537ddff225188392d119f1cc84ec1e85fba0c6123b3f9219f5ed98b10bea26b4a282ed087b6e9a427f875cdccd3f21595b8004842dc44bf370	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a2340f3961e57c8f05c483260d52ac5ed7116245d200cd78e3393861beb731d9fedfc4a588f3d25699c03824d5acd9b75a014fe54ed9f7ce8b2895f36d6af30	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98797cd4538e6d2cc55c7e7a6e000ecb141deaf6b74f62765d1b94a48d423a3795a751708beca87da948eac7f3195336a99088582cbac06292b515f56d54cfc5	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0bfbce3168c8761374dc261466e3070aa7586b90b1128c608ba6a842a643ac049e9b167c1bb726d6296dd639a07f7a23d16632e9648b7c67636f210840e385b8	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fd74c13e1e83cfb6becd1d801c7d1461f12ce3ad6d9927e3d35c1af8470b1854fc1743ad3be4929219fe4ca2bd036b8ed4080cd9a3ff4a5b984c3a9964366d8	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdfe748023aec70ab4e540dbb1a6451a2c2400c98fd8207e96c6e55836aae9fe9680b15188299002834c3c28cad3fbe4357219fba32564322d1d324c4b17749c3	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x889c4c789cf1405f52b077c11879efd8fe3e78b0f0061dd0e846c03537f0488b7811bf9e12263c5fbc14fe0e83d7bbd8848f10023f07a4c4481ae08c5043aaba	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa0674379e531a24ce9910f2aa1bec116e97acde08b7763d54271dc050c0aee21efab62c36407024665065cae4e65a02139ab5c92c65d8ddf4575919675cb16e0	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b9a32593e02fc7b540bb3c9f99441c3b56ca7cca4a880fa0435c21a45ee31053a4e7286dfa92897cf32f40f7449f34b90ef048de46797132539bde0181715ec	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb7fa2fd198fbbe47f418501ebfdef940da6dbef6d38ab13d66a4280c6aa5a36e6f39de34b47ee309df1d245dc21c45653f61bbc4ccc9d50fc3911804a14d531	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae653b182ed3083db9b52b19dde5bbf339bbb0f7fcb543d104cc32afecbafe57c2c4bd79c02cd0fa7f6a5f500b11ee8342687c79f3626083e48dc0d7ac634825	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6dd72190e6fae6b921a2df03a563568139352403c62dca6c9f5ceecc95d085f4a3ffd8afcf903bb87c13513f42ab3c0e299bbb45d4e4ff319b2d0a0996e7ea7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c4fd39e60b5cb1644636abdb21c206d21eb9f848aa799342573cc909b9b446009b2383c34cf4eff4024419acd49037ef91deec7330d5f5a76107548cdffefe3	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a7ef8f7118b5a3781d68e10e8e75562209e6ca20a0f2d44f7871f18c0cddc29a961e5608d993c942c7d18ba117177c9176b6b9ee0a64d61589e5191aad8fcb1	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe89188baea5b459fb14ca5a4949950050072419b01fd6c688196a9a30018bd0c071cbb0759e69060a871d97fb607180e782179147cba4ef7441f7c4ccd1ea22f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x179ed4665e9935d4e21fbb0a3010f3fdc2e3dfafb666b6cc94a40e477fd8a32cef6f1d8a3d09f87c4cbe38994738812e24e972ec4d96529e1d280ff73bd7a088	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4de745b999d539b120bfc11010b85b6689e2079bb839c2aa97d53f3d2717ff9ac6d8323a55aa1a80bf9fb83d7269e7033a7c88e18850a73abe9e86c181bc8850	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe19371a663cd9e7f90ff4fdf3ec1d42e93da1c13ad796f63f352577c5caaf6308b5efd2bb6db7802bc7d9ea9a1c41c4ecee85ba34a2b38740c2d1151276b1ead	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2615def80cb5d3bc34245abde45dd188a495b4208b01d0242d496965f29d9e0bd207f9b35ea8786023fda19c3f69eb34288b2635bbff24e8a384ea4f3506bb42	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf41057e7b26988267a5e46db26ab6f4db8c3f6697cbc2461af15912d026f387c16e58a1ab642eeaeae3583073fb46a14536f8b3e14b6fc5e3771a84baaa16c78	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77892dee3f069c271847640270660391f3b4b657a0ea86eb88d71fb875683873106cb2519af4d2e5009cdebba8652d382014d05e8afb033d6700c166fd100349	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c957a14ff145f1e7b15c68705637179530e040ab5a2d28f2791595a5d8a1b317556c051c8478e08fee38a2965ea0373ca6d08967e360860bd6007c6fd578854	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59ad486b5999f69a077508139d6f74a44f661cc37ab4ecf836342b8f91131d7b276a8fd57fd200bc40aa76e5d32904a87d7e9d636a063d109c51eba9588db7f5	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb59c16fcfa1e0780d9af9c46342ebb4e8a2896223e352af6b19cbe330ae974ab0547c38210d7dea6a32c453be8399c725189cc4d32e90062efd63a2c360ae920	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbef9f1c7163a7e815a64208522d68c696eacb706b0f980fd12bf53d3f0979532516227922bb6895e1deca91df8f1ee4722a73990a07ba23b3f50f00fc648019c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa5102083afcc75123b780e0a178fc4200146874333be6de1b6a11c4154cb3ccb73e49eae93c00e07fe72f0ff86b8590b039db33e31beabdad9e1ceed37b85e99	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf27471a50bd0b20fac0f6a10f54d142ca0aeb15db973402ecf9c398f3ac0b675a56cc85025cde8431fce55abd19f67758f5bf0087df222e5b0b5f1bc45f11e88	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d9f7f2be804e12720e469a0267b5fb1b368bc52daf3f251ce908240698278473fe63e919ebba44f7d8cca4e379c49b3d453418821e309acb77d02cb3ebb92bc	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7b0973e3438b80b9916d6749d1e8b8d30115a391f91f5c6ec8f715945ca09f832fe84f68cb6835714756a6a81fd9180b2024460d102ef754c484ac287ceadf41	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8a2288c0275acbdfec8d92dabea80b9fe065302a8786ef0a40614d1de6dbb03e5a3c166b3bd82fe57b193fbc83180b01391bdcffb8a4b157ae75a9b97e47212d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x42dc5246cbcacd0fa3d19eb750b55378a1b01f3d8362177b7585b0dc1a47748714b6095f6b2341b77a8d020b0dbacbfe294dbce53f73f1774f0cd79414a65814	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfd2e62066e47d346a6c8dea9397ed36018af189bc261c0308fa45eedd5b7716dbd5e642e0295d4c26972d2d79574812f949b68320b5125339229682fd1d67329	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x810ced9c9a78b90140bb0d704201a2ab48ae0e802bf187bbd6adc4bedc540b0bbd625499d78588f4648c73824a2e9f83a7804afeb46d9404912fd472224f7894	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc0ef46696806a9b4f97a704c961ddf6a2b0dbe4a4df1e1c1ffa6a7277c19cb77083c2d210dd46219e16400c44190912d5f221ca5816e662e0b074fb85387c6a6	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x461a307b4f7923b30a6a381d0e9d622279b926bc5b3a90df6f49135ca61b7ac5b96d70de0724f6e237baf833dd74a281e66504f5c8556d651b784be53f9aabc2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xee18df9d4351e689d8b8eccc3debf38555a8d928f96ceab5f6a7944f8112a86b0d0455be9b091a4ab6b43abd3f4d575ed0443715e1ce71a8a287515a64b22f00	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb8b01656d20fbe00c5be3efffc028c730b698f1eaacfe98ed2acf83f9aa9771084e712ce8465a5860de91ccbe12e90907db4e0681665ad7a0b6601bf649c0082	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd9dc2d83b6fd3fa4fd2040621e6cfe6f4461816548a49b4b93fda86f9c2468419dc5977a676b82f1dffba4b3772a3c34712ec5021cd5d5bd90448e6e05f8af0f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1d61fe454b676580fda844d3d35bc7a6f3987ff7883571420ea70e0aa2d3fbf899cb4d0332f0ac3cb5fcfb8da70718857696186028e3133ba8f8b22f83960b40	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x69f0488c565a72c7736a71939f5d15c83180db2afe54728f1f4364fc952b5d0fd3b4d0bc92d17a60f7f19a685d6e2e8ae35ef9d075964bd90a326c51729807f8	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x986059eb507e70bff1fd2009f9790bf0c653b33632d370f59f3b18966d693f010ea5669130e6e99d4b6ada58d88bacc53bc0190d31a3e959738f9f5111d4c7bb	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbbd9db05ef75f5f0bdf565ff302ef4e1914f614ffbe2c453fbc911ac1e4ed22bcc19929885a7dd626145624dc054745c4c4c4665ce5035a99cef0f755b31a37d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8c408dd9e8692d58ba94d5f265512016b2086360bce521a6d759ac8c5353f900076577fc011cea7a8644593a1d8784c1fb5f9604768e96fb8a3de01d6153c2b7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x64def236ec668c43aef0affb1b53274e41872f66cf47970910cf7af583e0153919d03ecbefdc0566c54df626bc91ee0ba64b5048f34d90d168796af0ea9da380	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf362b49d3243010c36c9fc5470befe2d8dea8a50142e502da2fb8e38507c81fffbb6cc225c1b9e06995894645c459b526ebbeb48d23fe0a1a21db0ea17c27b78	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x796f6587e77f0dfbf9e7855c6098f8f11d3732e3156025c95ea848efd9dce5ce51d30c430d65fcac72fe5659a52c2c22803a9b920667763a06f0a7679a97e715	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1963a88dc1b12ed4f37a8c5e1a1e97218506c55d5dcd7f8fd77bc630fab00b2ba19b3860169e3471ed0b7975fc7bd333af1b58909dd01d14fbfecf6f3c420763	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9c3058147bee60b9b827ebdc0ee0e8818fbd74ffd30304447fce5609a6226f40a1a3003306f9ada53152e057cff2919f1ff787a2470afef8f90b2fa2a9ea102e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa1188ec7e2dcd963e1fad7a1c3de6b6056337fcc2f305449d262bf1c91ad6e183f899480fc6e71cede71917f21daabc3776cf4b3366558195bcc634b24952841	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf47db450377de7a95699b477e6c50e16d9d41211e039dadff9e16dd92bb9ac2da0df851edea18adb7d2005e63c648964f5756e88a969d13c863ec0ed37fba578	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb6c8dfd61dac1168fcfa288e8049104e02145db501f313da72f6b76e0fd0385a13e149fa0625b4f4a121e57fe934872955ee651c1cc293846d10b3567e76f2ac	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x93ed2d1636460b90d4ea37e623bdab4d57c4b433679565b01ab929e9f1f247ad0d1885bcb92a4beaa0cd881c280d69d61ecab0926067ea9e5c83c81878e76d94	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5f6d671afe05efc434f90650c60fa04f4f299f13a26e0c33e6ee0bf4fe64e4a4091353d83b98d632c93a192de8b50245ade03ca7195eab8743a98de772cd6fb6	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4701f45ecbdb26006790836f976b5f4761c8ae5bb63ee9d81a9e4fd9ab81f6cb0d74abf5ee9503242ffd0fe866a7189c50406790927481fe5047db0317115358	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1b8e3b8ae2762c4f8603c6bf118f0ebcd7a49a3b0c18da4046e451cf0fa807a8903482d041e2ca801e3e6602da6bbdc65a6ef8e0aa2f16c032aad2c477294f6f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd80f21758a140f491d707faeb1e490656470fafb74a33931bd82159d9bc8c28d01a90c8736852cd1081fdcbb6268ec2c3e46cab6f2e5b46bb2b580176ab8a1d9	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x52d846d2f1a2fcb2e8c429287db7871646d62033101a7a6e0a8ce2468017ddeaea2e7a77c5931910041e12453b34c6097cb6ad39adcdfc09432fad333d1bf5c8	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x51ad6f16a2e7e05ed5450d5d42811b9e2371ce46b0a4e20fffd8d651c44488ddff23df8bc5044ce47958d0c6d6c120c40676f4418680c7f0238e3a9f16db1a65	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8be1b295f15e27c38e1f3f841418b9ef5fc2c6df88be3314306bd195e63cfef5c425a2d95ac154985afbc5a1a74c220a9a955ee88e75df33ef8b8d397900031d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf04e352e657f8b28381076dd0a6c8d0ad0341a461854d7036d820be10acdcf8af38ec642de63a8a14942abf3034def28b82773e3b8dcdfd652b48ea817a5d8b4	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x532ed9878d385ee8b8a941f1f162faea46b65acef26bf76ab1260a459ca4d2c3016f5c7627d00377e6c3592fa99610ce328235ebab2dc112e2f4ef38558c17d9	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8327045f0b3c049b3c107d9e83101709979c686b7bad7f5ce1b438a601ebe65dca336ba6e2146e1c10c6bac7572923d39534504fa5e10022cea88a6eb1cf1803	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb21240ac8b2dfbf6acf3c3b2c3ee4096817f94754b1471827bdecba03b9f5cf13af237ef56b106b8f7f938141e987ef5700cc68a3dc15156e7a98aaf7398bd5b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bea0b643161f9fdc6c845633c1faf83efce64ddcc494f659e98a448c3e930d9c29f0a81489fc69d16e57546904b35e0b51eb8575350a1ad0e47a45c97db3d4c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b31d979c78d82f6a668b661396181d00b3c8dc5487c05fb16c2c1891de1ee92631fd19c22a8c80d077bd80438088cf6b8ec6e4b0d7d847444bc7ff591f95d3a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0f619a98a7fb8b46661d395625fd9b71f30e3c06c2be592d474f2ca43589f9222eac48f5b33bf648fd5524d582900f49fc05630fef2ea22a900ad21b7b8eb6c1	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcffdbfef127d9127f7d24c1f89a6f7c0b2180b3ee6c0124b1a8cc625b253892c11ad370ed01aabae144dfd3a2ea0a68939016fbfe9cf3a0f759bb3d4fb09af21	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ab5ab4121ff0e569f887d8e63f9a2a341528ec466e6f0bb72ff509a1956277a924559d3025013ecd65cc9d44a66a7a7cab7db00b3911b979a7f551d99ef1d4f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x03abb480b8489296c4439997a444111fbe3cf06357d2ab689dc0ca164979c5625e487b7be01b8aaa83d050a08a56a0f901a59dc289a169652252aed85996519a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe4395b1b452d5b072252bf56cc2002dc2ef8d6e49c4dadc4247e203b379484570b603ba3c941d4afddace48f03c127c67240d2f00f8f05fafd8ffee65bc577d2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xded7b0a9d03b587fb40af7eeb54103e9f7edf4e7682ab51c0b5f7973cda7e476fd1a72c4dd4e0bdbd0f7ebd6a783beed5cea024da76cad825051c27f17d9539a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc42559cae44ab8eb6db5166dcef9b75217719ccf758db5d0421a1eec018bd9910788a31a9f698bf9e842b26c4b5ae0166397f220706618c41f6f121d4116a04a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0413efcf9843af5b81e877b316d2e8411a27a0d04739cba311ac8b13b82abdf41254d23b177783b76c752553b452cf9c28fb5618e460e586a79423dad373b3e1	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa645ef0684eee05c3cb374cd200ad0e1ba85f05d4c989099c765b1d29a3303dfa149b71f62a5d83867d735d6d1e8f286aea13f9bda9b0e515c1eb62c113c14e5	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x16a1f6a714543800d40162b84e736379a5b3fb99383624854384413dc461724f4fb2e831e7e6254fea269698e80805715338ff1427bfc86814ea5015dba498f7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x783d1390b273b8d88cf701a607551c10968e700df191e42da8b22277cf9b76f5f9727c47b2fa97490583a89ca79214ed53269cbe1ed41a4fa624222a3233dc32	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d0927c9db93ed7c53f4a4f64853a3f1b71016b9cb2000af666333b18aecd9fc0bf3ba71f6a28524107a1b3b4a178302432df5da564cc877e7c0b150bea5b443	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a706d387d5dca895fa41624c4dec0b8d9c076904b8b0fc29f0b4cb535dce72a80c17c4019551e01798f7e1bdaea93a67e14b2a00d8b9873df66a9d0e3055f2c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbcc4a74fbc8bc2b487db9e050ea7ad5a1106b6ed8dc54c97f30f495a6e7314617bd6443e2c1068ca1b49468b72b02cb4c939d07509d0bca1e0ff8425f25f02ba	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x26a6fe879cc5f03c38f081ddb51c5d761401feb1247f1651f412e92f141ab0555021a5bad1a5a911b8b2a87e1f7b50d78af904e3e4560492265e82fa6c49811c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7804d709a7084aa036388496604fffce3175683d3b12c295b6210530e0f45af44414d04a8cccbcdb5b67ca98416abd82ebee1ea9d86602e1ad8a4a4dff20f6b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e3fe3a6911551fd832890a640f801cac53c3613c4e3a287b7181214fce33476839e7df251edfc293a3b57c9c8086671c91cc2a974b0f79641da80e170ae94ba	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9a59082dd7446ebced5b328d3df04cc7869feb1b6842720184f2146b7551f9bea1254ed6abaac94c386cfbb37a9f515e3f16defee21abfef0dce04e4a9ada18	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f03e42f57afc490af1f0b310fe66aaf6c9d233fb3a53094ff173bc61c2f17f948184fc7f7b42ce7912baa30a140deed0576590a7640040488d8c91dd555ce5e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x45765a6eb22239b6ec63badeb9f26926e884978153338aba35b9dde17542f7cc07aac9d8353239318127518911058779598218c2764f83f5317872f394ea4248	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01c678dea74d88ee2c19e724a48853d93f3db24c2f80199acb2af440aa9ef8ce34667dd33b17c1425664632554f64367ab4f9e068de517909191351fb7502f85	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x697f41005bf3e2d3926d13d1691d3b7b48bb14a01a56449f648c0daffd6dec2d1352627444f3d523393fc86aa0a021794e1c7fe288af910646e7e1b92f17d7ee	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ef57f789f41e56a36b1ca4687f112b94ad453508f0772b2d082401ba72ee6a681c431802231eae1d05896ac8ede6fcb272bddbdf7043d5f02f232ded5a1d56b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x328814428cf9315aa7fb3e00cef914a131196d22444505be69a6605b6487f2c284d2bea14b7ae3538787e4dd291987e60ed24afb2c57bbd8c93d433406c26401	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d44262a6e2efc6866c7a28c8564b8fbcf88fb585ccf3065cbb2e439131f273f404863fe3f5593aabb82eb6a8888ac7da7648b7d761166e984009aeed3451a9a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f9bc68f30685500fe6d2029dbb2d3e4cec5ca98d03446b4450987c477a76749912ea83a9ee8512bac9982e4a3d74ebfb2a17c00a6374cb8f903635589e14900	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x10728e5339146f0aa23f00a66dec3112bd63f80d1b197ec1995a19f239c6c2e16df2bc05320e4ac88de32efed86e1f28b20d9e021bf9bd2e8f38a6bb4faa3b3b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x28bed386323deb805c7688e1328ec88028a5992b0fb197f341199407324e158f0be582e4212566a7d3e398bd61b78d4b3571d95a2a9f591ce0537dcb192d2b94	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b2a910cd51af9adf552233539e554dc3c4866b0f8d4318ec7ab0b8199ffd10c840da9a2db9fc5e32176ff487847098a06fb7da97d8d718d1b3b8c189e8164db	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c82ffead3a738556d4d5fe0ecc78fcfa18f887fe121165f36d302289f4d4644b7ceb48de94d4fc5a1fef40ada6f121d1a238175c16744d1d9357108eb5a39ad	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x097995f597cc6f2d3bfa02128efcc03c92e58f6fac20bf43624c0df37e154650edd10c43f4118e5b3ad88fe0b3cd2b516d5d6d0fb50fbfc55c7527953413daee	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb03360a0465d017695951dec6bd06182768d158fb624e134cb9b192401f608dbb3bd960fc8f98976a3e4aa3ca8a6517126f8ca2fe8fcb0c919430654355a0864	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe10da0a1ce2d0bf3bd4ed467166f8b0aaa91a6426bb5be6c69bfd0c9f865fc73b1aa0b7b09edf79450b4b32f5087d6a08803573613e3ae2195cdfbff0f0b1741	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x58bd57585206e25720530c6afc58cb8aacda7ece69e4b0af93a74f1d581a22405d7ef6d0c780c86d0c56a67471b370b041559f6b7f9094549a2a701493b05ac5	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0dd3f7b5b67ce579b725cbae136ee9dde6794ca7b95394f27481580d70e477f74f07791ead13d64f41d322f600c8139032d891b99c6503d5fe265d74914f3611	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x20bd7c64171716ab9f53b0b8a34e3697740ab1488ffec7723ac302841a1bd9580abccadd244e98612ff9f85cf354e7153571b71304f1e7263bdf32bd0fefe50c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8676ce5b5c6b7c58b3d076930812d6894604640139835e53597b2c43406b8b17fc0ebf12ca00ca0fe21b0e00368ed7f8906f8d3b3b83f1724144e558559c4d9e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb7df5d23c191149e6a12d7773365cfe6ed3e622ed4fb20c28b9ebcc7874c353da5618cdceddf07fd1f35bfa06aa1a84c2e5795a7d4a0ea415bf21f30d7ea0841	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c2705ecdc72497a81f3700b4f5efc08d9650f3999d63d7325cadad2ced75d33313f1edde548eaf94fd101aa0584ba5f4bf23da72bf754fc36292e6249edac12	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x42d5ff26efd8b7eabd481625fd021cab6fa8364f03f2abb3b0cdbf89876c3a4b862a8c0ed9b74406f893dcf3ed04f4f247b0be917ed5141d6bc4e2df03c95629	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb45fe45850d3f1394bf8c017d397db3760f3827d3172f54c6db77526bf5d37046fee684fe14049fcf9eb46c44ad34979c8c8a61a0253786897b53838035c8e07	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc6684c98adf661d3c6b94659cc8ed639a364fa821b88c5817bee5c95d8daf285c731501c921b7bb6b1df9b6b231848e1aae6253725e4ca294a254be1fa5c453c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c2fe1363a20a488d43adcd6b7002966508bfe0d20c302ec633f8b5f10d9687103dbbc37117fab8e837bc7d11a245817ef2cff212ac7a8fe901f4fbbb70c071e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x70d2e99d19064bd61b567310cb88423648a52ac28ea0c9517d087720dab3b356cc42ae493d3e9606e3d9b07c4db119eea6a4012b159d3ae32034dfa84c7085ba	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa82d74f0eeabd403f2ce91840ce6d5d2557088913d11005af5cace3b1d1867d574a1684e823fe0a59e74cfe7d6e5289f28f75dc1a43134d417c7bd288ef547d7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfda3fe8160265119c4edb7cb6c1544df600dfbada277281ba812c2a3e70053821648088a1d62f5bfd8afa86ae4678e7a764cdb663e6de3cafa7011b12ecdf478	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdbffc6c0b981df67f58eec633da13263ecfc7d31fa03e43a173e885aa964977824e80adaf7343571a80aafe51a3fd76fefc06d0723ac450f82c408273086d792	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9375c27e95139ccd721dbe849aad831b89810634754971bad15c21145c312484b01971151717cc5ff435c8a562ebede92930fabc3835981e114653d5f06a00ac	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x198bdb5b74f5e8765c0a27989d82735d24f3a818f7548fb1c21a1062698d7198b15b89556cf1d2403ba279062e48002c272ebdaee5d0f99c754bf23a4e318889	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xef26ea36c160d563da5b94e05d2e49695c22314ab5eacec9b12db92bfed1b3361ee6e0fef030b965f740b0e2bcc8dbf00d32f87d8778722ad47439bf62f97c57	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x215231200f5c42356ce432c223ded3ebdc656ee97f40617fe94e3a6c7a8ea17a865aff841b4b12edce088b3b2e395a3dac30d01ba7dec3de0aac2d240e9121d0	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1be138c67b08c3b116112289828b9b154d17f0c718bf07e6493e5239cbe6b656a918958aed213c46729459bb1bf40fba91dd36ed39752c38020f02f10e5f798f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd5153591843e2d535869afb5fe3b33454de48b4d2dede29f8ac04627f507ae788bb62cf65bd6aabd52ee94f7057ed8dbdd3b847bd9c9a9a4b0531047e799af65	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbd00b309659d6bdc9be913fc64f98a344d03cd2c8c091f816cf614d1dc925d0f824d78b9f5de1499228c93b7eebbd7c0afcf70d21b56d288d0725881268a771f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2e0d177f90016b204ce3436f66e2b3ff06613cfc46a2fe7c6db814844222d22e9ac0402e84003a72a59722d9cabf96cff359e5ad86b98787270a345573148562	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x57517066ab9fc2c1b6338648e46b100d1be5ef4362901f7f170e519b04da33fe2e4e5af4278374df2289baaa58730552a03b04d86c97d80a6631a50142d20eef	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a220e1fc2f13ffd0476958d6870be6d44749de49a48e7c3678db8b25cb57b68a1fd10f94f6aa6bc520ac02d5520ee915b701cc8a97aa04c2eb248344d5fda1a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5eb3424b35820896ca79daa9c7aed45949c56e1fabc43022c092421ad17165857939416f9319e0f0f4d2787b4083908f58b6111a08346f369b7832677ae2bbb3	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb11fa42b055959eb05a04d974cbc56f3cf0c95b6baf2687c207b73508a7c4834ae9e3f1f58b7481122cdbb86c45217528f69d0b51e4a62c6d48b477d79fd75ab	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1cd7a9de8ac4ff556441f009e6f88f98c201add3df9bd9658e219e715dc5370433ab31dd5f226894aeded401d219e9311942b81ffaf92c3d7d11ebcaece3f3e9	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad2a91eb9e63a9e4c8b4b07d33443f80f9d8b3842da5197a36396a8d57fe2d0b296346b6a57872197b016ffe32c885f9e1f233e6ba6987770dd91a3ae819a508	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x60f5874527dc05f1d5d67bb622b2a52872c2a2890fc135bdb76b1eb6cb34ba5f90e05bad577dc15abde31b344724e59394d74aedb2c987be6752ec98514a708d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa6eb6176dbb4107b8608a6badfc2956a661941583670f8e0ac96ca8cf5760b618b71d5879736d0c2522bcac814fe5b14511af56f831b8b394c7adf6fde0ed1cc	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x32d18470aea33f38679315233e08cd8e6d2201b85fa9907b2e226529abaadc37702a12fc7d68982f3e1bbe3e5610100540b062f7bdcfdadc59264fde5cc2cf31	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ec8b68a3249f2a5451d8386b24d61d7b973d8834c2d2414a309220500e08d94352d6a1e6e6fcde2521666e0b91385544f6b581e5da65b6cdc0710473a12d9eb	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7add3b3054d5b2a94b69f549d4c5a7fc30b2ce9c3770f037c897677c35e98af210a369a626713bb5bd0436e8bb42f26fa45e2f1b525736c8b8a89dd7ca88f577	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xed5de46f817cf26c5adad38c083413827edc0aa799646f10c33e5791f319501b8f8fc802680d6562919b4aaa7cf93b014cfcbd0ce1719896da52b941521fa03d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd50666825b35e76de6401e2e4f3eee3744a244c69b164ecd0aa16600920be051f49095e8e3d3d17bfaedcf24d2695145d71e7e3e56dac3d4d8dab27bea04aeed	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe09eef9a404adba1c94e829caf1d09cc8b7f39022c20de15594a0d39c91fbd3d39d7ece8aa210dce80ce1cf31651794b3b5feb5c28d873d7fc41600b976c91c6	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa1c8e6f60c3b4f021a88118f31cc674c0ae166b981a880acb9074b34380afaf18726aca193482d748d09b33097b0bd352c3fe324bbf4c776fd3c975a163e1965	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c973a248f6665060741c8578bde55aebe485be4510e321297df233768e3a4d003c0f12614be9b1f11b45f221520d85316fe1e52f9380cba13ec12459f785a6e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6f6b076b7ea1451f1ff6f3397222016ec99efb748f269a4b4b8fae5546ce90572802b6d91c9282691e4414e34eb4c1b7d0810be255b7b1b80f25203bac335813	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9f5c69d175e4e77b1b41d326f79e76c7c0b2e457646c6add031f96d5f1beaa1e1735ce930195ad867c7d40ff7863c7c6e95445296990b806ea345e20a3fdeeef	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x785f8414bd8c2aee16a16bcd0b26ecc08b5cfff508ee7077526497c671b90d37fd22ddd4aa4a4e91be05692a91c8e1a2c60bb8f8c3c0c8beff15bf405272adfe	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x90e956a84f1b219f25df5a7f28ad1dd03e0c36d4a917e5c6465a16ca595e135f1417ec2b7914d1b3f794204298297da4d6f46b87770c30b4911aeaa4336ffc0e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc33e3e37b3cc50cad6407ababf5d98607cc113f6a9e64e9f63e369358e36395776cf4888d85321245ec72c47369b6ea906a878168ea5dae059894c0c9c783083	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x33d829092d0a2f66da7f215cf50295ed88a85c771e9d57e6aa3d8ad2ccdbab54af04632cf8000e8826fc4f9976d72c58a6ec4587c8d8d4e5b2874e23893fe3ca	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd765bf17227904d4d16c260ba5aab53d6a381d6ddd9e6b6ea3ce3cc3704c9be3a59e0fe1da02515377145838934dafb6269a6ec661014beefcc98bbc72e7dacf	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x872ea97ce6f9daeec908c42639464850dc62b374027d5aac896088a4f5729e2b8d8ef396f526c7aac46c04796e36f812377e57d91604c2bbec5d53cfd8f87f09	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x390fa5d0688d0aa2bf68a6498ec60feefa742f39d684a423aa170b2efa2f55d0f6fba832fae2b595a38cf1c280c4e84bc6d2af37873db8f0a7d0637a0c9ad1a8	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x270b0fc6a8e2c4a470b93811029d87983cda04776860bf541a597fecef7a3b31f377e5cb9193c877bdb15d96c59716e854cd72c483d3f47bf9c92b2b8e030718	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdb81beeb5119e098953aae22a31ef0493a74de905bd6b4c699fa8e61c81c6591e6ecd75df6c294699b29cfe301e41330b3e5353ef60330526b791c4e9901e807	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x59667eb2425915c13448f2e9f2d33cead3828602d2601c143085cfab100f931d230b98d5ca1307d95e4ce92c37db21c4e5ad58475baa3029031e5314c59b1ce7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3463a69fc1e8274e3e2cb7fe4daba51f3b5a0c16e856b7d86a4c5f15ee4ddce752c32ca3ad7cff5ee1736ebd8547e737bb78c024ea210a7d648f7741bb87434	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaa022c3e4b2864b95bf681f28694876dc1816477ca8a4a6db4303b2b46edb1f7f5b916ac4ef5fadf388ee8a7a4baf75265c14966034818a206330e9a5768031a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc32cd6dc9b7bb020fdc2b9a6c7def1d13340a22782f5589fb327c1ae4a6453fd8903b6ed81db16a5dacc6533181c15f5c9d29afe30a786b85e56d0c6af6a71d4	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe599d1ba069b2b22417ae8c0931b7d5aea657905c63abfcb8fac0ca0e39a067d44d3f1219b3332f8afb60794a039eca74972f1cdb70474878c44f1c6fa6977fe	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x10e3844bd4b72183f51f14ab1d2fb0a1ec17872d3b9adba9924703dc6b3e2f9a272fb04ab57d37c30671d4a23ee12812f204d03dcff16566c8c505e23950afb6	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2d44e470b82c922a4ec610cb58ac879c3859672552423815ac725587240f643b51ebe19490923e12b1bb47417a9658eb79ae34a13d18b2db737209514920c2a6	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1807755d43f8c9f345488e8a675f5abf0e8f29eb96b0284f0478b62935b092c5e420a60ad5145739996171d608e985e08f999b79efa7ae1add030ff4f4ca54c7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e05cf2a10a9ac3a131256fd985fe320798b1dc1d677acaddf7c67d46d250f33ac9a4bd192b96e93fb6b64a43d12cd3d669b076678411681f8dc1d8a44516ec4	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x53059af68a385654bd58ce173798075a5f511c4e9c9dfa98336e6344115f8eede9e0c49399cdfc8d9b75662ac74e7f633e71d108183c7b3ebfd2d0c4df02240b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd9fe4f39f3678606ca97a14509fdd605410703f3b83b22aff6d2e70abab9d67db0af496a3477da64bc64e73121ebfed3c2a26ba0ee11d26a44a810377399e448	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x998084d92e429f86e2fdad4b8101e554598caed216af516689df91e44405559c55ffd68c2fab8fcf197a4dd7a2519634af1bc4467158621ce73c3047c510d015	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x49f2c0a8e108b64fd7ad4297b54e414852bb0a96f723cd0a6b18529db6e0cdda8910ed2d3b65bb4fea3e3a52a4d651dc1d6ae84c65e1b8e73e1fc6fc9e578e5d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x76cfaf6258498a15de3e7f608669c4f06d6ebb50e96208e3c1be89c3dcad51d183245871c66a40bf8676806042d8e157b16870a37aa6f887ce46ec9dd0e79ce2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x44ff25c34e3b966e015c99a0f9d6c0c5ccce3049b4044fe9b6c8f78e4d1abb86c2352b95f0594ed11a6d140c47b44cb2de0900a192fc4dbf88bf7e1c3dd5421b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9e3f94bd47549e51aa9473364f2f417dd24a48e9b8d268ccf57cfe22b1a6494b042888a44fb76fdca047087d758d082f70bef5c1d20727236e8d6232487bdeed	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd40d1b360887e99e67645a6cab0ecb0af0e1beb5e1d99369e9e6a262aa2b9faaed024af2b8453115e607b1cc5a26127604e03b667c9a6a21107caa011ad618e4	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x423bf0f5b1299529d833e3dd2d06186ac3167d60b0845b6e362ed9e915cfd771281ad8ff5700011f1c82b5488589456ca658b54c967d8ae573c3a739eadfe339	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x940f6cde75b1bcc0bf00f2f9cb145e8fe0e0ad5040c74992446c8fc67d36c74c56f5b71472923a0fe0a6d7f7d80f69727b4897e1fa89ce4decabc41b7ace2b2b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc3aa0dc87efef85eeef8385a51ddb5a5ba9e07539acae2e11cb6799830254d3c725a8ef63149cda9fd4a59a3e4524e732b0e38ea8256df933ff5219746aa1ed0	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xefda293f089b9032c9e4bd0c2690ea42a835617b40416470565a3e853932feec1be04adf76107dfb437273d5e9648a7928949fcee2cb7bb509f2c24a09f93d3b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0efbbc2dd25e3da3bb47fbbbcbb433ae47ec65e75f79871d93d08451729d95665bdec6c42d9338c15b313049e278ef46507c376191dd027c743d224a4b5ba183	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdafe2a427f429a64544b5f07d447719b2fcb6afcc4c6b6a9fc0df37135fa8bbab4235071c9e745fd2b677c7ffc6612a3a902adffe8ea88777cf67e650b21f802	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd3c133ee289ab4579585114e13d7f35d1a0567b5c87e257efc9948a47a8a75d2e2f6b82ab10297a26e1e502518a2f1b36de61c1a4e82df5b88deeb09a6df9af8	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd584fe0a4f0bfe6b27ab8f13e0bafe7001cdc99d7c694a6f6653fa16bd60c4a70fe19a1cd7bbe39b7d55210e44c0dba3ad69f8148bb1cc4482bdb1db0f486658	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd87cd4e26742bd0bb0e3dadbc4d479d097d5b4f3c3512041a87182005193f308ed8331fd43be483a6e8056550f049b3c8b6f193c4ba76b918fb9eb7736e89397	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe5ecc2b1b33221b1e51c02bd8c317ced502308403a69499b9414e6ad4d77cb967e87fd2f3c9e5344968c6ec4f799660ba6fb34f59d762eb1b0890f50053bd899	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x74c67c75eb3a143096dfcff25eb2b0205159c0751acc96aa1241462142c5a1cdf786f699cf5131896c72d371e70a2e8b4087bcf41d9d9d2d4f3ed91691e55f69	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb8683cfd3a4b5951eee0222e43de3e665d6a93545531f991443bdf686548b96a4dafca74d58c95cf2848279b91aac4a2854a5336aaefbc349dc74d2442df72e5	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9ab0ea31dbcfb4a5939d0c5d768c7e50092a6e967690b0188fec16f6f4e3618b9c747e117c2126d3caac483acceb2eec98626123ab9ddeba851828d1da3b65ac	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcf7fc415001f971d9fb7e7ef61d91680b375868bcc2de166d61a1353ee3181fc90fdb345f8ce4c9a023f41f65963791ad4a5687cb5c31c1ec2feddfefa97e6ad	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xabb6a744e88154daf70ee4b4a8f82b6448a847cf83fb98fa98f19f1c74305fd24fabe2d0b34fe3c5547f4e0cd87a675bafc32e17bfb8cdf9ab22937fa028d7b9	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6fa432541cbf62574c7455ef00a43079abc873348614e3448ed74c5ae1740b35ca2d3749c7fc61823adb6d77a8891b5ca8fe8e2f259d3d73779b4ad19032b255	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9803887567b886cac330c978b3d2f14057128055affb56dcff6a6c429843881b70fc612f9612140d56e9740fc32fd6c788074b85798c7db914bbf800194cf2cb	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc539cf8853d05933fa5757182ec8a82946e46b05aae0f7b96c9222f2aae71a63f06be9bf63827b4633126f7cd27666a013e9faac3f9acce85d2d6e89f9137fe5	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc577464f2c5122e09f40ad07f2584bfbef340d2705b35e2be42ff6ac4a5448c102448ddecb5f1fc52ce85e0796c1f83c30f34757164bf95a690a33e4f5489e12	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xef8d58cc1dccf0e6f6216086159f924350d81682d8a0dfcf0baf1cfd01a88ce960d9c6ff4580128768c17ba6c25764f98b117c6cb74f2aae5072ce2e42c8dcce	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3f59043549d275ffae5497417c6a12c11bee278406a5643d96fbdf26405a9a782015113e35cce08b469d61fce842f3e9da66eb80692149036ca23300d3d8df53	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2aec5c1973d6059936c28f867dbc553039aae458adbe1c48506731079bd08180c00bd258acd98f35b2011c99c02cac624675b8114aa943fa642a08fc40c9dc94	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x66de0f8518ff079810eb82bd61561e636f25d3385023a766125a14c56731338e17b12566495318599cbef0d51f0655e9cd8ea48446b037d4dd2b1e8a6edaf910	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa3efa6196fa388a299193ccc5ad31f0c9cc9c57f8001f0a177c880bd9d6610e3d45aad81aff303e69048b8833eb64ab16df6230a0cda1d2e84b85484edfa20bd	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8f521348c5000f8108e68617acc25b85287a7642ff573cc67214acd5dbcd85c5aa82d681c23f731e11af548ec88204a9c935803cd717d863e9029fa52158ab93	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x74e71242590ad6b4c28fe57c8a2e27ada1b003f7f3f5e58c2c30b82c76300c1efbd1dabffe5333288a5c44b6a2a7b02e3065c8a3d0c4823db35862916a6b0512	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9f72ec32288804887389715aa3b1c6d278aa269d916602d00ceaca10ba438d4c747d3842a911f415b179fbebe018b74840bcbe7946555576cf2cfd65ab317410	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6b0f1ebf463d3d458486c4b6e6b9e262af6fe28a1cd8303e6fcb8be1e5b0ac425ca5ebccab9dac0595f396b50193ed796f40afe64764ab43df7926954908034c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x521aa0ca368e3364072446c858827312cfd93ce7da600148320dd28d2614d9601ab5dfd657b417bca77d46cc1ad2c12f35b16a91d82e216b666d7016ae943a16	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d9d14226d347ea2ce4fc2b088786dcb60d00ff69428bed218cadca405b73d726a933b179130456f4157f86d5da81e21d782c9fc95d4b2172c36ab215bea67ad	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xebd2176c34521207ecbcc0debc4e0a5b9ea613c42e65cf49f6c1b14263205d648c34484118a0825c83ddfae7a7dd497786dc0fbb892c43c1d279e71c9283241e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x21afcb1e7dad59f2e455743cba90f55b2624993ba010a41a4c0a618d836ae3b4fa05b63814100fc5eea7babbea9c5bdbab23a393436e49b1874477cd52920597	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7fede99ea55c76cc76e533ec3723ac08d697272ff7a779e4c1053ebde6545559b24a16d5f4b8110b1e8aa7e81e7b6c27c77a415970cd8cab4452c3c1f8d2dcc	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd299cdc9dfcf2c8f7166fd65dd555cae3804f6993f505588ee958cf87578b64f4356a5767bf2b9a4548dbbaa8fb0d458daa91397f515b5086f3678c4e474b07	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22103da8672510221830f6cf1b39905f224fad6a885cf2e6487abc1ca78d60a95861c017ff9b23607818ee59c7d55d2c0734be7156c4f0053d08ba784ce12f0b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9778748515ea66a11940e6d08faf39117b39730e78e9c4c6437c8eceae14859b904dab6f4ab765d6ba77f94f779b56c9a07d304c35f1e92dfec6b5a093dbd773	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbbe5c3a238b490f9951c1c851db210a102578fe28cc59ff42b391f30868a5023caf31219645e72e569eefc74a17e8b9ac1b090b85626f0ae736e83ab42e74936	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x201984330d4fa1bfe01a893596a24aea4513c5e0cb4f5dfd9bc894bf9224de6f2aa5257480ab83522cd1356eac5d2fe838b58aa02ebffdbfd683aac665d908ed	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa08edcc11d568b5c9d9306fa803ef27bbcc2c3f01d6b06a7d7091a43d725cef4462aab4e705965960d733108132097989e5163e0c7836f72643599a47512eea0	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57eb13c29015bcb5dc8bf8223c2ea0333dc5340a9b8ba500bdd22429db3a6c756c7bce33ba27f943bc25380d46b220ef2bbdca9a64fb2818e4e5991ce84dfd7d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x60f21b6606beecb1ff65c8cc7b7acb820c7d4d205ce211c4070b4f9a944211c92bf7b618c2d50fbd99909ecb771b13a4e292842291bb16179ffd318f62617f5e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a46ee6eb7784b4a4c1e062b2e4dbe64b5dab8e4ca2ca3386b930faeaeedeecb6ce774fec0801000b9c94d25e929b8b48c26411bcc74f810fbdda2ef760036ac	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a52dfffe9974ca681879289d0b8c13b267cc2b99414deea287baac68fe9ba1d0116ded33c3b9e296a57557bb84c28e8ed0a514dfe5c3cefbdaf8186ceb534f2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa993548882a15e70491df568ca1fb1ed1e6f28212d55be8c8974d09ee5fc08333195b99683c6f5481354de162a02c2c267b0b3d4579bf89831630d57c607fddb	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x274e149d443048e12e46daf41b996ee86de0d322e46fba217405f39574d431df867b95ad842e87e9cd47a66698bf5356ac394e998070bdb9e960f3772177eaf3	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbdf86ae3bddd4560da9cab43bf6c5e39ce070578f1355555db946ad25893ee8887977442aa3fa6bd5f724f19e713564087806490173ac70a37aae8245e306b9d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x978ed7eaaf25459f4de5830122944e24976dd5c4b753d5ff701a0769fbc7106d7944fc61bb766f3704e8411af8934608862e0ad706b9a7531e1fd13c7fa9f3e7	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9de5ea8a0cdde011e5489c9c32cf9f9f0b557b577a6691a4dbd256d1d75a303b49d28858d64b1ef0ec5888d07b34bdf523ab227637dc201b0521d641c3587ad6	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd792ee42de33291c14f949f7e920c09bc30720ea06bb96a30dc36bff1379b6e2bf7f569adba842664abc52ca087f75dc2033635a9defd41ed9efbf9b46ad41f4	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xabc2efc721c67cb3fe39f4d6d6e527d9eef47320875607b1391028b6de5162d5d133616129d5f3318846c3fe0ae93d98c2df52d4397f6fe4bebc3352f66b232a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf1d1cd867f33a5efd032db71c2c348bfd06fbd90a17e7cbc004a1cce2876fb71b66237593fba963f2d93abcfed3d3b00b1116efbefc275aaf87cad299178d770	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa8053a3c350688e68e88cb9c32f73d27813cf7ad6540b356e3d7c883dadbe592854a33c460b0dd43168a00772bf5e8d95efe59ac2a4d99faae450fe4576e2f72	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x953e4440efcd5accbc2c55d9509cef071b35557292e6e3876ecf133704330a4823476c294cd686576128fe985c1d1dc252359ed257aa686eb3799325cec5ccdf	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd92c908f1b16f09c5cae536f8bba1753e66be94790e6b75307eecbda682ce137e3003e203a15b55401bb32c4e3e72fc4dfcc06973c1bd078459913b7422d4788	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e3c602f56092fcfa2201126c33a442a57d528c8e83bd4b9ed35d26a55cb57ec99bee7550557636d571827662ff0361ff8111a56fdcacdd20298a572aff03423	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x01cf75059cadce412de440b1da32e8de346ceac95d8006e7992da66829c3a6cd889a34e2782a067744f3c810a5210f6ff674944e395c39003577ef76697c137b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x378d5c36d62747693a1ffbe2e88f9bff3164f5196db3bf4cbe4fad9a70ea52b392b5cbda49dee832e796177eb68754de7f0fa2b00ac1dfa60d72e8e5124edec5	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2dfeaa77a3e2613e2c090d80fd64335873f178d2f198c77c1571af18d4f04268592d8896f099ee990d78dfddc1686993416559f35120822f7d219768e9056aa	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x93e25b6f9b9f9ce7b90902227ad8434f52397c00ebf04fd96f6e4eae8b325f9c2b5cbb88f93a536e7d92d7351d3cfbd13120e1f85b1d6bac467c4edb3a6d2477	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9e371c75757c7278619fa47e0f3a896336a3b4f50906f317cc92d38f0128785e8cebfd1f0c5a886fa79873a4a17ae9656b7528486afc53a2e93c4c40f171ef9	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570364126000000	1570968926000000	1633436126000000	1664972126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x31878383a3462e229d242d44db5ddcc72d132d960140565599a72c6f538d16e27d8936a1ec8a151300e2d8b6d094f6228197ae23fc16d6fcf5cbcdf6b8988d4e	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1570968626000000	1571573426000000	1634040626000000	1665576626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0ef4920ddc75d8f18084409d34b627004bf2d113836c0a3ef1af9135f5f32432e8f175bc0d530d5be251a8352d3d023a7584f9af56fda096a4af885fce0b9fdc	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1571573126000000	1572177926000000	1634645126000000	1666181126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x80495fd020e25bf12966e0bd2462c3ebbc716a4776745e373ac6b352f9a313e831ad99ea91c71b421f706b3a487d4bd06d53f3bebcb9193d41c8f34beb33e2c4	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572177626000000	1572782426000000	1635249626000000	1666785626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2149f2e7426c318e59d38754216a57db481454209b970984381512c17f0a93ea0c3a0a98f515631b051caf365c1ced5f2e98dda5e8e186993df77000b448a992	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1572782126000000	1573386926000000	1635854126000000	1667390126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2e4d59d6b664b37d593593a472f786d2ec2baba2864ace0409917b23c150504e6f569102c2220d43db5560c7dcccb5c8adc082fcc60d9cb62651cf3f3bb063ba	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573386626000000	1573991426000000	1636458626000000	1667994626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x321d2eb42018595aba80d0a35ec8b39e3d2d623eef666efc72390e66672ae0635971257b9a1367736d5cb6fa4301c8a99471bc5742ea82e902dfdb9de267298d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1573991126000000	1574595926000000	1637063126000000	1668599126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2c9607cc03bc149cf28367c7ea22d01723988a861b9063e79f6e8fee78e0fc15264497b9131d9b3146073a3ebe7ee168174052dd0a2626cec07f5a22b001a1fa	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1574595626000000	1575200426000000	1637667626000000	1669203626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4d2b19db808f4963bda42adf9ed0269b53e9362f7325dc2491250fefe7376508045704cc710f4d42a6786a9e176380127cbc0ab9c593fd03893ef98e128c849f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575200126000000	1575804926000000	1638272126000000	1669808126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5f518a99ae4cfe10a24fcfb1b103a7a01d6e9fbff9930ba2a966299c8f3dafc5dcb045ae85df3de27f601cc598e28d8160b0aff95dd5a9ad4711b5991cad2f91	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1575804626000000	1576409426000000	1638876626000000	1670412626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x34de5e58fcbbb148cb8b81683711ba082118234b1aa325fefe98f26c7afa55affb771487092eed6d746c521370643a4d248cea6a3b20de691a9904be88b29b23	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1576409126000000	1577013926000000	1639481126000000	1671017126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf95c3cb9de8de1b76a4aa23b889da94e51a7a4c16ebcb07a16210eeadddebb367311cbf67c19e9d2709d07adef41f4137433bebb8e9dbf70495180773774ee9f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577013626000000	1577618426000000	1640085626000000	1671621626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3c080bfe552333e249829f51489ee4add1ea750050eda568db5262b29c82bd8cafd7f72a47cbf9de3f6bb9efe95b9f235349d97247e0a8c8b1ad762af9ec7be4	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1577618126000000	1578222926000000	1640690126000000	1672226126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf42eb9e6bb6f2edfbffc38a7e5e2329292fe577da85c9ebb15093930d1be0dfe89b0864552c7d5a7def62646afe2501b26487370fbecc17ada81a7acad96881d	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578222626000000	1578827426000000	1641294626000000	1672830626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe19987da0834475301910a48fa5efeb942f0b992ccf1c9675566a983b6dc4cf236bc8ba477bb29551bc0c9c0fc87a03c9bd80934bceeccc19456a0e07d0a9501	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1578827126000000	1579431926000000	1641899126000000	1673435126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x17bc5dc5519d6f083aa1234983386b97fb4482cc221bdd91039376d768905152ad07759540d6cb40c900af09f60eba81b747e3c9287bbd31d68d7556e7c88dc0	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1579431626000000	1580036426000000	1642503626000000	1674039626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc0c76aef2a0dd1357f657751f40b84f91bb290ce11351eda1a2cf53e3d9f0b0d5712ece923493d8f0618371e48cbdee1d0c181da0bd86b419e05c4377ddbd658	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580036126000000	1580640926000000	1643108126000000	1674644126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe2c68d8149d96029b133fc043c60f1026d03acb7ec58adbcc0b508fa9fecc46417966d3d6e1f8d9c41ecc46ec7884fdb2b298ffd5242bedd8e0474f367e49efa	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1580640626000000	1581245426000000	1643712626000000	1675248626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x56101e27c07d85de86aad686472e4ea8fad2525d13322bf83abad80fe89c3c4215a8b23a6adcf66d5f16498fd2a5ddc0cfbc12f96fa2d580fa803420b9d52b31	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581245126000000	1581849926000000	1644317126000000	1675853126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8e7da4a2ab339ec1f040f2627de8e9eef2d52cccc5493a2fcd09470d981f35d632cc81e8a582244a08ffc82de3efc59ad8090d51ee8b3b102d34a12692d81354	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1581849626000000	1582454426000000	1644921626000000	1676457626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa81d8d86ff728c57b80f156554d8c8bb8e83ccdffd0447b8a4e8374e3d6a746891edac75135e6e0bd57c4b4a69d422bf5794ce4b389696d7c046f1f1f0a9297a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1582454126000000	1583058926000000	1645526126000000	1677062126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x93d8de7bc67420baec5bbf7ba440cbd57a4e37638bc85d511f0aded03f073e4b8e0210cb4203f6bf8390f565c56dcd982045abc32e683d93ce2d760965a94ae1	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583058626000000	1583663426000000	1646130626000000	1677666626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd29f881bed1da56c76c6625e47358ac46e5e9bc30a162f33b127e28a1a7aea4739c550c00dc55b08d204c3f5aa12e0c691f19cfd1bd0956cc971baf3bbb27ca2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1583663126000000	1584267926000000	1646735126000000	1678271126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9ef98801c42c975ffa27328c34ce0f39a55032c4a501f1eb226a96727e16699c805ec5cd3d5cd12eba0786fcacdaf2d3c8d128a865dd5e12be71039bd53bd04c	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584267626000000	1584872426000000	1647339626000000	1678875626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xceb2e2cc7ff41a6860dcede92cadd3d6cabbdd5b3e826f5202562db6edd3b7d4cfcfeecb1b49f092ebe7c95f4ec4ca395a8f8ff880ed38b00f4d17d26bdd2ac2	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1584872126000000	1585476926000000	1647944126000000	1679480126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x63f1092d5a65001c1fdae1b7893cb0456390978609cca229918279b65401b4955543ca325e4afcb459e38987e898825b768afddc69fd3cfb402bb7157da96fc8	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1585476626000000	1586081426000000	1648548626000000	1680084626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbe43e91a2fc734ad47cea24190874163bd56b6cde717400ae2e7b83ab05bfffd4ba41091443e8b80233c3a70714eff126512f60b6c57182d8004c1c34ac0d502	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586081126000000	1586685926000000	1649153126000000	1680689126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x41b070ae5fb20fccc0dabe9aeb3f375725d69965d67cd911e3f157455a6f7a984cefbfdd6f64853024801315dc4db735efc04bd10ab25137e80773508e32442b	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1586685626000000	1587290426000000	1649757626000000	1681293626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8c3e135fe0ee1756f38031f401f588891e1b76dd3e0e7874b06389f58ca4cd8be1fb9f1dd97f5ca52e6ccae7c0831dc8308a3e065be8a679616bd61136a868e6	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587290126000000	1587894926000000	1650362126000000	1681898126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x99684358805d2c5ad5efc98c61fa6376c33333fc0fe30753bf6901098638957eab7f057e7ce00c10847ee8a17f50696ace82cff23d8fef9764c1536b88942163	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1587894626000000	1588499426000000	1650966626000000	1682502626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x087fb3387150f60446e19333ee8b577b5e09f892066212b8f5ebca2164448cfc17e171807718717475d240607879f442b96faf474bef2597d5a90e404b317e8a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1588499126000000	1589103926000000	1651571126000000	1683107126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x17730aa1fe5cc4c4a95ea87be44da7f767f9ebde7d9bd9196a112091b2223f8c326fd12205f88505a141a0b090ff346ba835fee4f5e6148d7ccfe02b86b0e1ea	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589103626000000	1589708426000000	1652175626000000	1683711626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x19a4ab8ac2d447976eaef5d538ecc5e7fe5ebc45a27d1e4d7b84b4f93a8bc55ac8d7043b1dce433202b49ce58fab4e41c17aa56c5e42f4660243c7cef8b6f68f	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	1589708126000000	1590312926000000	1652780126000000	1684316126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
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
\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	http://localhost:8081/
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
1	pbkdf2_sha256$150000$EKrDxWKl9wqC$6hMkJb58hRAJUycxigI8RPUo6hQ/Hqwl9XIiupYevcU=	\N	f	Bank				f	t	2019-10-06 14:15:33.156881+02
2	pbkdf2_sha256$150000$K9r7CxhcExeP$tzdGTWg2MmL4WDqVc2umJ1sjCJC+wzpL+H6xYBc8cDA=	\N	f	Exchange				f	t	2019-10-06 14:15:33.218961+02
3	pbkdf2_sha256$150000$8tMUpcY0T5Hx$ubSc2ydWctYxsfaMJU7L5jtwmeNx33xYZSup3CAv1gg=	\N	f	Tor				f	t	2019-10-06 14:15:33.271044+02
4	pbkdf2_sha256$150000$Jumkov6qbAyA$1KMLK/0c2MpLMitcu8x2IqWmGKzDVHJWdrqxpQ+htRQ=	\N	f	GNUnet				f	t	2019-10-06 14:15:33.322449+02
5	pbkdf2_sha256$150000$V7XmAYo5XUka$7tu04qo+zS5CxdOrY0/ru93Y3JlTocxeYfk2K64An8I=	\N	f	Taler				f	t	2019-10-06 14:15:33.374333+02
6	pbkdf2_sha256$150000$MGBX5FgEs2B7$HqnekkGv8vKAcrd/WBd8TzDZhsnBAp3DiZ1IfFR6akM=	\N	f	FSF				f	t	2019-10-06 14:15:33.425392+02
7	pbkdf2_sha256$150000$5WshXzfs8zCm$RTSZ24LhhgRRw0lLXDEwZBCcUrfQ9Ntbl6RtJ4xYdro=	\N	f	Tutorial				f	t	2019-10-06 14:15:33.476013+02
8	pbkdf2_sha256$150000$GPE6Ccz3fc2K$O6D97poELOmWLgk43TczpVKEoO36vCWNx7h6En0f6OE=	\N	f	Survey				f	t	2019-10-06 14:15:33.529066+02
9	pbkdf2_sha256$150000$zXY4VWfy3bOX$Z4+e1if2ibC6vUIZS3oZcXmS41/39Q0Bp8VRre7AicI=	\N	f	testuser-vfvQXPR1				f	t	2019-10-06 14:15:43.570038+02
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
\\x7bea0b643161f9fdc6c845633c1faf83efce64ddcc494f659e98a448c3e930d9c29f0a81489fc69d16e57546904b35e0b51eb8575350a1ad0e47a45c97db3d4c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430343141444145464232424532424538333930454332313344363931444643423341304635423436444433333435443537303439424246393830433738313336324238304638384639413734323636374230364436313931353346303944463238443839463934414543424337323438384241364143343834413239434434453832463644353030324546303935463845454543314443454131463545453043454643363444443537344342364634314539433644314336344533353639423835433234434336384630394439304346433838413739413946393039343638333730394343413346464636313835414641354445324432434532383546323323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x5e2ded649202c4d0fb1ff036311790497fac5de71183a701e323ecb889531b3497a5e4d47e1ae85b48a9a147ed194592afbc74fd1f583e0c86891cfd4ba6800e	1572177626000000	1572782426000000	1635249626000000	1666785626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8327045f0b3c049b3c107d9e83101709979c686b7bad7f5ce1b438a601ebe65dca336ba6e2146e1c10c6bac7572923d39534504fa5e10022cea88a6eb1cf1803	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304339433641333538373337353241364533324537304331393036393633333635364543323631353543453734433544423531314132444136383745313441353942453530463430373534353833463743313938313342304332374338383243453633344446453637413738463731303846354330383641373333323439353932363543453644414432423237304545393435414137313844364237434144374146444530364436433834424144433232443930373946423437393942323638454230444233383737343339423932394245354135314336303841314234314433303041304243353239354633443843454143354339453838363944464243303323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf3fca51afcdc653ccc1e4d29e000a142e83e9149382f4dbf5def6c6ad0aafc62a7465d8f4b5f669ac2b62a600bc48b548b5b7f42de022dd82ab33b820a59c701	1570968626000000	1571573426000000	1634040626000000	1665576626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b31d979c78d82f6a668b661396181d00b3c8dc5487c05fb16c2c1891de1ee92631fd19c22a8c80d077bd80438088cf6b8ec6e4b0d7d847444bc7ff591f95d3a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238414438383433433444453044353146434245443143453045363342413238303244414139314546304137414644434544343346333942414138444438434135393637373942304438454230354641443439374431353943334434333242444530433741444336394234453838443432433143383533314638414641433242313632463638303243373741433633334144353441393346413645463432363939414432384331434530444538324341334243323633363942453833364137463131393336383332463338333232453544394139443837344436364244353344423335453544373039414545384236433441304642324531354333444630364223290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x6063db79a4899322a653029cf3722239d03dc6ff026cf69d3d9f196e5090f5dcbb2d942425587cc9a2346d92a822b32ab2dd0a8b579ebd3c5776efc836f70206	1572782126000000	1573386926000000	1635854126000000	1667390126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x532ed9878d385ee8b8a941f1f162faea46b65acef26bf76ab1260a459ca4d2c3016f5c7627d00377e6c3592fa99610ce328235ebab2dc112e2f4ef38558c17d9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243323945444544304341433146433733393432373345454146343536323530353339324338423539334434353933443031414132334643303738323435373745393543363236304246393234323135434537384435444634334538444333324534443136363539373931453639324235443739324135314245333043374245353345453433393039464233433442374637373142424144423034344536443236423845354535463834374339313135353246433645364132433939313943373143373141463433364242344539343131314134433042433745313830433034334236413742333842323744463841363241383133363932324141384445313323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x5aca73d8dff0b71c0d75673f966d5bda2154bba4374cc971cc732e6e0624acd673325a6f887b80976bf25400b5451932f700bfd77bc95c2f690112308a3a5e0b	1570364126000000	1570968926000000	1633436126000000	1664972126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb21240ac8b2dfbf6acf3c3b2c3ee4096817f94754b1471827bdecba03b9f5cf13af237ef56b106b8f7f938141e987ef5700cc68a3dc15156e7a98aaf7398bd5b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304133323036424234434544363736463239424435414144313241334138344438383539463245334233373936433934454246454239303132324634344333313835463838323237343535423345334438374431324330383045433043373133413945353136373930413334453932424243333135463039343135374644303131383330383835373044463843413830344144464431393733323434354444454438383533443037373337464539373343433745413644413235343232454641393830363939413437423644434530353831303330303238453638373741413833454442393834333135454635354145313930463932393230334235323530363123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x448dff1b0031047ab39292903852e534ab3c9efeb40f07007e51bcdaecbcf8a5adc761db91be43c2d63c2ffd81d68b291c920e7f8752460cd3931ae4c638ea08	1571573126000000	1572177926000000	1634645126000000	1666181126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ea56c0d374ef55c3c654d10099ad40d04423659499c51fc684881b66bc3644b2c8dcb59f74d8793ff380670a69d38903f8018030d66df2a974fb49d03e88235	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241323839383235463242463330334546433838423736303143373138414236313734434132384443343845444339353333303038384139344338384132344534464131464336423834383939333634414245413543314645373843314142393039303145413846373545373844384538343642343232434135314142323435334233443343333336363437383246343633344441313333383238313536453241383434324641443538333136363430364236354535343330383030444345464130324334363730363531393237394635364231393943373445303432333844383732353844304338414244454538443131384246324536414430313343353523290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf24ffb856f3266620ac0f21c50551cbecb9b856f7a6883d47d6e69c120d6d205d33a026407a5052ef14cf3d425463d4d2593cf1927ae4db21b89781480e0290e	1572177626000000	1572782426000000	1635249626000000	1666785626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3073e10f602b828b4f66190244891f669866cc59c7e90566b3ca4eacaa962105ac293987aaa8df89ef35400c6e5ca1473160b0e093e57f5d53763c7fe8d7326	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241433441314645354538434538363746373143463432433345364246333044383441363945323731394242413635423434324244423243344245433031393137303344353842393536313734303834443437354638394339383733304634313841464235374131463843434538363939413744443245344446313845434232323034434635434434373743434446324635444432303841324334393337333944443041354446433239314535353530364542463543443032354346353331314636364341343832433634413146444634393934453644464445343943314639443944453843383631454234304642423444443734383632454231414546364423290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xb1f6fd695bd8cfccd8b80cd3eb44e71e7ce028c6914b70c82c60899b25766c5d4a6780df5c552d8db2cebb83764f4b0d084c8a9afcce50f4f6001fb756be790e	1570968626000000	1571573426000000	1634040626000000	1665576626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8142382f4cc72d2e270c8932da8fadc8de72a4b6ee949bca2f52aa2dd0e329df64b664d56755e148b583be71828808a4095282053afa53c7205819fd9f72711b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304441344137444237323633314132344444353038303137423331304639394141393533303433354134394143454635423937363731453738464338443835393832333739344439354436364336463839454134393630453141423636434337443635383232333231344335384243323234434441313739373535413145394646373246353436443533393736444241414530423243383334314442454331324534364544354137344530434535444142454244393241303841334538424338433446313642394641413631333043463539414531364537464335414643314534433646433244453438363335393841464445453643313843303046413446343323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x27f7d2e5f546d0907bf4ba97a4ae417e766bc17689913cd3468966b686834986778a2653206471936ada705e2777d0d3e5ce192bddeb7a3fab692a2efef0ea08	1572782126000000	1573386926000000	1635854126000000	1667390126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6f9bba13975c8904a8c9882d4860a3762016835d096fe2845ee8a4bcba10d1a8698198e5a949141216ffdf007d24db3824c987f176e98c7479de970a146cb3c2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435314237303631424344413643423933334541464530323537333738373032374637423134434344393843363545414645463736443245423543364630333835463337433442454337364233443242313832324246433846314541433236393844313846394131433433454438363539464632313632313046374131393137433535463545364335374138333236334246383543373239353032324239383239393545393445413642333941414138393730363138303644334430343345303937303839354638453532413444373837434634414435384331433143304242384230423032443630363942303045383242464533463038373335424146423123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xc57818ab2b144f3c6ad6988c832f9acdd34cf71eadd769ebb228d60ad3ff3f417eff15c8502e06d4cfde53ea7dbf545d7182c535d92b7da638345921dfee6308	1570364126000000	1570968926000000	1633436126000000	1664972126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9ef88baac495ea7337b8f6893a1f57083f0dbc6d904321bf1bc76f7134cea9c8601bbb539ca9d94e1ee8ed41ae73222b2913f90a14a10385d90e36704a1c038	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246453638303837464643384341343138344543463342423335343837303134304637374237363334374345433931363932333132414630364335433732333937413534433744393931354645423645433442364445353743453937463946413333313336453745303744323146354537394532423046394536343037343232324637313142433545423038414531303244433345394433384233374139353838324546393638463338463930383039444538413342414133423042444245434541433243393536393530343443374130344432353642373443433044373537433046463933434146384332384534313930393134353639394336353334363323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf844781e81df759381caed61a8a2206f60e30e213d061a088bd387ab69736fa7648278ee2bd32c83402859697dd8fc41bf30a2b2011e202adafcaabe5a0a6601	1571573126000000	1572177926000000	1634645126000000	1666181126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ec8b68a3249f2a5451d8386b24d61d7b973d8834c2d2414a309220500e08d94352d6a1e6e6fcde2521666e0b91385544f6b581e5da65b6cdc0710473a12d9eb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304446433645354546393835413432424532313134444445424636333236454144413846303631443342424234353530364437334535373043353938344131463242303738313634334646304145354243333244434637453546333539453535413032313646424146454530383236324344453731353144423941464334463941463232353443453344344646393637384531423043383238363833333443464544303541393735323141323139393532344134313042423641374641463031413645453842344531313735383033413938373842364644344434333331313346443634333136413646304537383236454637383635424233434231354632394223290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x8168ea5b4f37c7f5af54bd0592db076b9b97e63aa6f99fc7f895ee6445b283de1dbb325db6da9d26a276116a93fd91ceb46e45e053880b30decc1222bbe4fb03	1572177626000000	1572782426000000	1635249626000000	1666785626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa6eb6176dbb4107b8608a6badfc2956a661941583670f8e0ac96ca8cf5760b618b71d5879736d0c2522bcac814fe5b14511af56f831b8b394c7adf6fde0ed1cc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233413043313833323736384631443041363331303543313042334531384637383032353937423337424535303538303533453933414633444342433538433146363933353634303838463738413241394644383936414537443532334334383145464241413432324541374534323042333346343841344332353938344145313936343938353238304643393746303830324433343645363935313236463938453844424238444539433338353941393946423843444244433435373439453944443244444242303033334533373546364630463939414331334332443136354139313635423741413235364645373433444336393530433339443132343723290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x49253bff0713ba2963b6c2b52b9f71d6d336f425242383cfae990099880aeaad4e4b5cb7dc1d1bc98558894af19ce11b7838d53a93ee47bad80c5cff9b068204	1570968626000000	1571573426000000	1634040626000000	1665576626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7add3b3054d5b2a94b69f549d4c5a7fc30b2ce9c3770f037c897677c35e98af210a369a626713bb5bd0436e8bb42f26fa45e2f1b525736c8b8a89dd7ca88f577	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246463041373434343532463231453343453235303546354637414444453636303245313131303535313245313744303144373744414543414346303846304135413644413433324638413239353445343436373037423531453936444436443033324635324438453641434337353931434530373233304143313532384541464239324538333837433231423442454534374143433643363938353246463746343236353943423830313945344344324344434646454545434441413245414243454444373938363245424141443443353139433744353544413443383137453435463134443234344430434232324335433241394430423635434139424423290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x615055d11cae5d8247eb717f9aac0e4e04469769d4d959d28e2414234d283a1ece67a59d7940a26209a03969fb0d90787070910ea8d825b4ac441b5ed081a409	1572782126000000	1573386926000000	1635854126000000	1667390126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x60f5874527dc05f1d5d67bb622b2a52872c2a2890fc135bdb76b1eb6cb34ba5f90e05bad577dc15abde31b344724e59394d74aedb2c987be6752ec98514a708d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304131343438313336354631463433383035373745343945364435313244314344383138374137353444333544453044354130324341433036343045324432354337353544324534413737454632453130453731303335354441413337363045333432383134333243414442304245363341453242423634434233313939344442394639374330364546374243384336393434343642453930334145384330343838314538333244434639373036323045414630453637304142454144324332324238353445443146383641303134303737393746443131443830354636383143304335453038453735433135434641324546383241433642373146413443383923290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x79080266de8d333aaf676cc879b3a92ed48ed7d1f57dcdb4f76e27beb63d9df64acbc311425124933145df9cc70570ef7ea8732abdf0570801ef1396d9f7b406	1570364126000000	1570968926000000	1633436126000000	1664972126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x32d18470aea33f38679315233e08cd8e6d2201b85fa9907b2e226529abaadc37702a12fc7d68982f3e1bbe3e5610100540b062f7bdcfdadc59264fde5cc2cf31	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304133304141413246424542454233343432373737353734323137373635344434313438413644384237303944323732433839364137443846353141303333413732313345444431414544323039383736334436354546323936383733433733454637453635334541433938443042344342424233463031344331363645373933343341393732424445454337353730384236443734383130463030414239353138394633393736313033344345353332303933333236434637413342353745384532433741373946414543313639444344424536423546454436363143394246393536333934444444384142353939303531333932423033413132413334464623290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x896457d04bd5736058a80698849a6c0a3ec24ec0418e9753fe38f6e11bbe3373cd0b11c8917702209660dcc613ca5339fb49297ede7bc51857ce7b0cd04e1a09	1571573126000000	1572177926000000	1634645126000000	1666181126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb03360a0465d017695951dec6bd06182768d158fb624e134cb9b192401f608dbb3bd960fc8f98976a3e4aa3ca8a6517126f8ca2fe8fcb0c919430654355a0864	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433364142413041413532384544373235424635314134393936444335414639443837304438343931304237343942354238313336383730383337393137443932453439393330393639384641423437464546353344333532383245393243364145323334384337394438374546303533434144383443373830353242443436344646454344333531433241334238453130443632313133303538423233453236323744303141323243313942433738434638334346434238333545304437323343383445413936414531343236413339374138414333373146433037394534334636383838374644333544343839433430414343393532424635373230303123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x42576c887308251afa28c79345747eb10983d9328fa763f177cc534b8195432a7b63285037f43e424e95c39b8ad7d810917e05350e0f68b32a6bfea85b8b5101	1572177626000000	1572782426000000	1635249626000000	1666785626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c82ffead3a738556d4d5fe0ecc78fcfa18f887fe121165f36d302289f4d4644b7ceb48de94d4fc5a1fef40ada6f121d1a238175c16744d1d9357108eb5a39ad	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946414641463236443537453346313031334430443641424231314432464132314237393844333245443941464233383232384236374433303643364336454143324537393932413130364539424642383046443436323639453939443441343730364439383443373146463645333345343643444433413338324135373443413232443530333132443231393145384131413836363145383435354346434132444235423030443833463534313845434339383237453843423435453645353842303845393639363634364434373238334536454131333743354346313636413242364434354634344138373237453134313839464137384244384441363123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xba6c11310b055b07f95e7f71b0afd67839cbd821ef220ff57aafb54868a3db4c4ba0ef79a18adce21035d5b1bc1e708141e03f19e67f4b636da1431e26a7cc05	1570968626000000	1571573426000000	1634040626000000	1665576626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe10da0a1ce2d0bf3bd4ed467166f8b0aaa91a6426bb5be6c69bfd0c9f865fc73b1aa0b7b09edf79450b4b32f5087d6a08803573613e3ae2195cdfbff0f0b1741	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243463434444632303731384232343134354239333143373445313839454439304636303433394541313139423538344242393043353534394342343146453032434146353031464232343536363936383143343943394344423944324538443633323645354330363634444641313937433131424641383846453335364537414541313842314439454133393941383830374146333746464133363043333835413044344330383336424139363742454242353145414539373245313238414643393935444635423641434234314342323044333737393145324630394238314445433133393234303333343537394141384244453133313032344431383123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xcbaa2569c5423fb8448a3edac8bfc1955d18d861dca1968838327d3e1b683dca364bd417eb44ebf73527b1d2a113c574c39f65aa7a32a20a7157e8d08eac460f	1572782126000000	1573386926000000	1635854126000000	1667390126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3b2a910cd51af9adf552233539e554dc3c4866b0f8d4318ec7ab0b8199ffd10c840da9a2db9fc5e32176ff487847098a06fb7da97d8d718d1b3b8c189e8164db	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436374435384432463346423930413346453746393344353635393946354335423946354232394132313130393946414441324136454644374237423236453332433434374344383533394135393843453741413239324137464432453532414138314144433242343845433634363032304133344535314536353845313544454444464645304439314335463944363441313137383832334343463646423437353246424145313132393043454337363130444644443641313836453630313233433439443732413539353230444131303442334633303445363041373035344241433235423437353143323445434138433535323338353234354436324223290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x9aec1ba96bc42b653350b70b0f04fce3bd5f51cb5e4db3945d2cdc8ccf279b6fd37ce0c44080b34c781ca9b8b2b0f8caa9e2ce51d36caf130cb5e3e99e720109	1570364126000000	1570968926000000	1633436126000000	1664972126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x097995f597cc6f2d3bfa02128efcc03c92e58f6fac20bf43624c0df37e154650edd10c43f4118e5b3ad88fe0b3cd2b516d5d6d0fb50fbfc55c7527953413daee	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334323443303733394530444546413336313741434546303344304239424435323631384536383846303341424335453931303042303539313335343038414346373445444341413633393344413632383444434534353042454533424246323241444233454232423643373346363438304538333532343844363742384641433443373132374646423035433944393242323343413135433433354546363039334335454234324332443945323633353936354435354138384335393345363932334441373937353139323444413336384146354536413730434444413334323030433337354636303235393733323830364635433537393344423042444423290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf6dc08f380387ec42dfd6f247c3c10d027a57021cead4bd4c1bcbc6994842dc53cc7e791a5c129a0a46616b3282c611672f0d83754bd866a2539983799ad760f	1571573126000000	1572177926000000	1634645126000000	1666181126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e3f94bd47549e51aa9473364f2f417dd24a48e9b8d268ccf57cfe22b1a6494b042888a44fb76fdca047087d758d082f70bef5c1d20727236e8d6232487bdeed	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303935373143383439413233423430443830323432433933374330463136383142373346334138323844443330343545464432344541364139384531374332344143313933353836353031333533373442434244393337413237383042334534353536384438323834334236414143453045443942353344424638343235383131463039313346433935434231303830384141463637384530414531453439304144363932383236313833434634433338353345304238363438434530463035453338453838463246303246354639363535423830304345413636334631393831383530454541343638354635464138433545343542323131434237353930363123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x6c89e311b63ba8788d1ab708cfef266af48ce30f7b25fb562341642fc9ee11d9b520f22cccb2b4776ed49f1600a9aa616b175b01eedd182813ad186561260d02	1572177626000000	1572782426000000	1635249626000000	1666785626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x76cfaf6258498a15de3e7f608669c4f06d6ebb50e96208e3c1be89c3dcad51d183245871c66a40bf8676806042d8e157b16870a37aa6f887ce46ec9dd0e79ce2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241313442384533343642413436424436464141333746333835433737324146304241463945374633354134434530303432313434383041453143354638324638343032333144443331323544463434384535383835373934323637454145383537464143454332394431383237363331344533353437393331444432383334423245314138354134334639413931314331333636324233463036413446333834333845454645364231304331454332413336424432363343363441393936433636303645463339383344363832444432353139444137353736304144364139323532393231304545304137424646394245363545364141373539373933323923290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x174662f7ee321f51f7a79c08595a31cc290a6506a4c835b9e4a8d3b572b8b3f736939d585269958d7a224934fa2519b71bb3acd9a2c6e52df010aec4a476a50b	1570968626000000	1571573426000000	1634040626000000	1665576626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd40d1b360887e99e67645a6cab0ecb0af0e1beb5e1d99369e9e6a262aa2b9faaed024af2b8453115e607b1cc5a26127604e03b667c9a6a21107caa011ad618e4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304533414533373843433543433637303239373339423133373545423443454233394237304241394344383738444135313432443831333032374242453138443134314434314637364430313030374543314145424231334433343037313931313035393234454433393743463535383344414633354539433836353033443637333844334532314435313344383245463442363936344339453244354441394139384532413832363643384246384234304231334439413530464346433443353142343445434638383231463630383239323035334136413736314441323133453730313736413443313230443134424638393344323245393245433644444423290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x8f71115833dd3e86a3a6213ec4d0e777798a2da2f1b93a5ff1d27dd1dc7e807ab6cea4f8ba3979792f9a46e5d423b89ecc777a7ea96c8ae94864997baeac6504	1572782126000000	1573386926000000	1635854126000000	1667390126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x49f2c0a8e108b64fd7ad4297b54e414852bb0a96f723cd0a6b18529db6e0cdda8910ed2d3b65bb4fea3e3a52a4d651dc1d6ae84c65e1b8e73e1fc6fc9e578e5d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304341454242453245393432323143443244383237433933393638373743304641463432314545383444433739364235414643453643374430374336464435333633393741334638413944363843333543464136353031434333324330423142373530363842393930454342453438303434413043443041374538304630413742333535434236424635393635314233303333324545373831433038343832373042333733433036434642384638323746444246334239414246323035454631303733354333333644433034304346453746454438353943353341343434304335304241374438453631343044443332303741323037454141414442454532463323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xdeb56d381e7871851647d28eff6d5d51d1b425cdc0d7a30a2cf4a8a04037a45200463958cbd6648099aa9a297697434134e1200bf789c2b3a373cfa39a3a0b04	1570364126000000	1570968926000000	1633436126000000	1664972126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x44ff25c34e3b966e015c99a0f9d6c0c5ccce3049b4044fe9b6c8f78e4d1abb86c2352b95f0594ed11a6d140c47b44cb2de0900a192fc4dbf88bf7e1c3dd5421b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304530433138434239433539313343343743314133433733464633333036333046393943464539304137344531323037353942324433393131414537463331444638423345423539413035314444394642433846324638363738354441363043364232423744383238454138383742424143373535334332433246413233334638363636414141363033373545463336333035344136444539394238343431444437423536383146393538384132373236304231423935344543373344383643314335463842353035303441333338433046393439414446434545434544464231363641344233434137433746364242323542383736334244434538423241334423290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x547171b098cb968327ca0abd1405db9d4890bc70a334a1f34903b9bf828cdd07af6b5c02527dc8faace7363d6bbc8984f9af14016e1042f5d1b8c330c08dff0a	1571573126000000	1572177926000000	1634645126000000	1666181126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x80495fd020e25bf12966e0bd2462c3ebbc716a4776745e373ac6b352f9a313e831ad99ea91c71b421f706b3a487d4bd06d53f3bebcb9193d41c8f34beb33e2c4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304535383636393839354446324343353244364438354346343545344144464339413435313936413045394144354646373542363031344143413143384331323233414130334445353541434343384234383744424235464534423133313044353345434646434632423235464246363044303338464634364631354146453837394439373741444434303733464444354241373241463941324234344235334430364445314133384639423938454641384441363730453230423944364133463434413739323239334432464630433734383841373537374435454335374336463843384631323842443142453242314438443034364434413034344341313723290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x1582355dc554fab1c6b69e533e7f98f687ec46cbe8ef749abac22c067170d7f072e69a468f59ea87e842e2936a8e37ac99407771b096465ca9a63fac84b94c07	1572177626000000	1572782426000000	1635249626000000	1666785626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x31878383a3462e229d242d44db5ddcc72d132d960140565599a72c6f538d16e27d8936a1ec8a151300e2d8b6d094f6228197ae23fc16d6fcf5cbcdf6b8988d4e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303941463744344632433937343243463244454236393436463438343934353233433046323033443034394632464343363530393441414134314244443432354430444635464441463630303330343443303832444437444445413142353046344645453036453041443034333342333746374534423844324130314535414346343038393546323842373434423730313033424645423430333130373844393339453531304439344532464345443130374343323131433433453344414539453338393638323146373332453542393941394136413643344334353541394439453645383443303934423839363133373933414442373543373032303742413723290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x214ab2946f598164e6cba2593986b36eb342334f30f61b8f68ba56d531a582e6831102a60aacea8f53fbdbc00a7afbe9da7ad91f8d453f6979f23ce2cda00f00	1570968626000000	1571573426000000	1634040626000000	1665576626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2149f2e7426c318e59d38754216a57db481454209b970984381512c17f0a93ea0c3a0a98f515631b051caf365c1ced5f2e98dda5e8e186993df77000b448a992	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304531373537374638313442333136354232414335433739414645363541443630413437333632453730394533414633394337354637343937304242313536303036393444323939353846444145414633334531333244314137393931323232393132343938443830343833313530374341324636444133463844423342373143334545303946353942303733464237334334393042413631423339464343304146444144304145433836393736443142443944324244353938353741333439463543414138333339304135393144423139313931434445353743354541424331334641454439334141363745393345423633384436333541393631443735463323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xc98d58fc4cbfd8a162a58e52c5c3d01a90bf3de557e8100745c3925dd24a2854cfb68d6daabe85af5b2f1f46b7bc395858f69dd074e0f574ef67648959b71009	1572782126000000	1573386926000000	1635854126000000	1667390126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233463730313143313032423143433336433741333544373941374444433237343735443242414236393944454439313131433038354238303235433143433535454438453536344430374643334441443944464332373242383245324535323231313233303630394539303732313731364244393137303145353034323546303237413343343530324533434145313134303145333746334244384133463433443838414532384431443737353945383043394342303843414439333942384137414234443839344631313230374543314534363731453245443636463142304446354146443030464334444136333038364135303141423232383139344223290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xa55e20923aa1c8acc43d41aa3cef3161b38af44f0bf875ec221ca5615bc6da46b5613f0a49b8cd1784ea054e743d844118ea70b9a60479dad638f0d23a9a3d06	1570364126000000	1570968926000000	1633436126000000	1664972126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0ef4920ddc75d8f18084409d34b627004bf2d113836c0a3ef1af9135f5f32432e8f175bc0d530d5be251a8352d3d023a7584f9af56fda096a4af885fce0b9fdc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304132414333363344453632413744333631304130303832444538464132344546344146334544424631383534334537464438394234374436333842394131373531363638344644384643334239313138344136353532453938353141424344394534384442303036463039353741333445424534463934373136373235413339444146393039344430353333414537423646463843413730314332363432333831433245393930363530303845374436303443333844374235453330334531344231343531383839383235464134343536373343343145394543333141303338373935373730414645313643353446333443303534424535323741413242443123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xd8cf500c49446a3ed45b8e9859a7e71756859097aff3e785acccc55adda2d00542311b902d8667cc363f52b05060ca18d94f8c1c8059faf6958af86a2c374f0d	1571573126000000	1572177926000000	1634645126000000	1666181126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xebd2176c34521207ecbcc0debc4e0a5b9ea613c42e65cf49f6c1b14263205d648c34484118a0825c83ddfae7a7dd497786dc0fbb892c43c1d279e71c9283241e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304134363146453443433235424530383231443233323346343338414534353841454639373330334546353142454331393744383230413946374639384439464330313241464341433333454434303146454644413734383337313139433241454144344241423131313745393945443844414442463644414531304245433142413241423943393836343538353331314435324439393731383734383431423039373735393534423133464433373341443030324242343233393038384132433642324645374546454138383143383943454445313432354535313732313736383143304531333245443943434541343345313331304138324331463930433123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x29fe263d3f4e371cfb31f77ab86713c78fb2d6b2b4b08f5258ec155164eb736db85802900be390a30316987f08739a3dfcec1620f689c432fddbc1f0a68c030a	1572177626000000	1572782426000000	1635249626000000	1666785626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x521aa0ca368e3364072446c858827312cfd93ce7da600148320dd28d2614d9601ab5dfd657b417bca77d46cc1ad2c12f35b16a91d82e216b666d7016ae943a16	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304337394230423634303133373046303032423331343444334245464537423542444137373833444536303241333736333744343945354336303836423941434133433038353039363144394533423536444242303138414144434435354539324343333239434133343631423336413932424342303746354243303936363945324537413145444645353835323943303345464436304436333534413039453946343330374443373736464145344136464241303844313937343035353035423238384638443036433046354241353833333942433933453139343532433731374635453736343034423838413335374245454639444345443331304145303323290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x538afd5be86954a0bced0d187cfc6c65dd4ee696696339e4b55b8b051d904828d7c5051a66976a0f203f57fbcf80e684233b9d66b93d1dda9b03176fb33c490d	1570968626000000	1571573426000000	1634040626000000	1665576626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x21afcb1e7dad59f2e455743cba90f55b2624993ba010a41a4c0a618d836ae3b4fa05b63814100fc5eea7babbea9c5bdbab23a393436e49b1874477cd52920597	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304234354544414235393832414237313831333431463844434333374336413441413544334536383830334133414237393936433336304446344144364145464337314439333532374332303543394131334630324343353245313035384238423642343242414535373534463545344137413139353235303432444230373431394439443142304131343636393232394531394441363631354430454636424434393639323237323044384132423134424542393237384130304646333544323746323136374437383232434246394543363639314239394230333637303932453133313341383942423139413734343935423936463444364437333635354423290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x3b643676b115307a574d64c6732e002a03f58af429c4443aa82e92fc93e07d76c3af64796834fe8e20f8a3c8475d158a1dce33a04be9bde7c2d1840fed62830f	1572782126000000	1573386926000000	1635854126000000	1667390126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304142453043393732324233383442324546413141423846434437343145433345333345423438313345423539353238363332424131343635413535364236433644413045453045374232393330383045464138414530384539334633323739383030373735453133423230354343433846454433364235303139434145443243443445323131323431424244353139444241383045323437374236464246434333383939453844334130353734423638383735453433373034303534333232423046333334353546394331343941313645453744454643354442343334433344313935344544354136364638443545323634423432323130433045454539413923290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x72180522df3e761005789a8616f5c2908dde9a80ae368b079975020821e3638a97c27a521562622932327d5fc2cd2d2f55c5b0bbe78e7d8931b89b432da0770a	1570364126000000	1570968926000000	1633436126000000	1664972126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d9d14226d347ea2ce4fc2b088786dcb60d00ff69428bed218cadca405b73d726a933b179130456f4157f86d5da81e21d782c9fc95d4b2172c36ab215bea67ad	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436334343424334453832343330344538463546314444303838383644433239443435464436423135314238314242353941413538414434373244374642354545323941353435303543393943323631333941353639303939373437373133303342394439384646453536363631443638303038333234333430434438323035353843423930333131423542313535414639384632344531384137363539314232303143343933363846383437434130343132463846373936423135304330464242364334303535383836314543413038453433464239384335454538354430453735434442323230353643354246303934313945424531303133313838394623290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x0ceadccbe635023c26c62dd990fb5245031ecc720ec1541accfec214fb0a1766f9409b560c953f675d058b7a626b43fee76b070a59cbe465b1197b5913764902	1571573126000000	1572177926000000	1634645126000000	1666181126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x42dc5246cbcacd0fa3d19eb750b55378a1b01f3d8362177b7585b0dc1a47748714b6095f6b2341b77a8d020b0dbacbfe294dbce53f73f1774f0cd79414a65814	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237333939363941394331314636373138373341344139413042393446334531464134313430313530444330383441353843353032464544303236464246424330383643443130444641333441323742454244304238444538353342314335443542444130463745313635434334393432414144324439423631333843373537393333333830344139373034324246384236353639303743383941424331323234343144343434364332303844444443434639453630364635303530413144424545434433434335354438343232373435344239383445333236333232433544454544333945384139363337383941334334323846304646383942464331414423290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xba094c0d408176bbd427027e8286d542228ea7665515a2b02361c65e7b4c44b871c058003e635fc05844d0e2d38f34eb090f4321ed9d6cd0ca010eceb618760f	1572177626000000	1572782426000000	1635249626000000	1666785626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7b0973e3438b80b9916d6749d1e8b8d30115a391f91f5c6ec8f715945ca09f832fe84f68cb6835714756a6a81fd9180b2024460d102ef754c484ac287ceadf41	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338453433433336373133323045363841334139363835313732384139334438313833333142384545373943453645383232434231424641373446344644393035413239323645353732383935433441313636364335434645433844444341363442464139394345413635314338393839453737424236423534394435303945433841363033384236443441434537364333393841313641354637463744373135393034324545454242343637314431354645424132433744373833354245444635343138363636393532394441453636333638463931334243303735383539423744453636363938334142334134453545363735414638363139393034453923290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x91c42aca08ac0dfe0b4ec3db3b88a90e3e65354f45edd9250d268343cd27ce011e632693ec88622c0c0f083f802e98b09b7d9bd27ad9dc0da886472f21232a02	1570968626000000	1571573426000000	1634040626000000	1665576626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfd2e62066e47d346a6c8dea9397ed36018af189bc261c0308fa45eedd5b7716dbd5e642e0295d4c26972d2d79574812f949b68320b5125339229682fd1d67329	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304343444536463831334430353031383435394532364641453242443439314633384333424533343032343030443041444341393046354544313242464341343732323046394246414643313732413938374438453235393242323133443236344436393046334239413633334630413543363739423342333743303835303342334132323846444541333844343537424134434537373745374237424444454138344332383441414634343941393636304241393044343237344335313841363032304432443931393945313938424246364344463635444342363738414534434132463932363143443734373142463743343743343238374437413744443123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xec5f96f0363333d4d200534cdd08dea91da9a766e7cb998437cb2bbf8f94e16620c804b603e03a753b0f38558842c87810aa217b90416437f57c791dc5d3b302	1572782126000000	1573386926000000	1635854126000000	1667390126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9d9f7f2be804e12720e469a0267b5fb1b368bc52daf3f251ce908240698278473fe63e919ebba44f7d8cca4e379c49b3d453418821e309acb77d02cb3ebb92bc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304530333346413833444144463837373236424638443734303539323530434341353746454130383937333946393242413934333735453842393046434235353845414445354134463936374346424238463339444139363638364241434234423743373033323339333142303245463732434242424544333543334446374432373043354644454533303335454335333839413830444630343542353245453030353344443930384444383835303437334533363336363645323836374245333635413437443045433241374641373342394633453841394331304433333034304333363845423741374245463137364532333633423333353544324443393123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x67278ba7669773fefa6564518ffb3a58e4bc33eedef500754b2620ffa745669b966018c6e1b4f4d0370313f4d8933696b492791495d1a3d87a6c28f5f65cc703	1570364126000000	1570968926000000	1633436126000000	1664972126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8a2288c0275acbdfec8d92dabea80b9fe065302a8786ef0a40614d1de6dbb03e5a3c166b3bd82fe57b193fbc83180b01391bdcffb8a4b157ae75a9b97e47212d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304437314636304430363036464431364646433733374543303841373330363442393935424246454631373531434244333339423141313934323343413043463045434142424444433435333532413634413436393043364341353732414633304142413745324446394643353443343032364638363341443745464138323343453236353636463146413738383936324541303944333444373837313237374441353942304139333937373031334338364133374531383630313642344339363437313043444242393644373938443943303431363332354636353243324137423645334631434536313241454238373833463937383638384642304538313123290a20202865202330313030303123290a2020290a20290a	\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\x672a53863fb6db174f68e4a60395538fb5b7665d0e98224a45b305c6c295123ce71dd149f81c3883e61ebac723f1b9a1adf0797c7a2cce675fe5658236626a08	1571573126000000	1572177926000000	1634645126000000	1666181126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\xda37cdd2b6b9cf8313269a25ab96fd4d44b7172c52c506d8e6cf604e09c6f94b	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\x9caceed1064228bc121384b5031e4cd8f9f83a0fde62ff8ec690b1197626627361c31774e083c752c91bde07189532b47d15cb89ab897e21179ec902e691d60e	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
2	\\x00914420cdcb96a2897321a3673a906c07c0d04a13f8ab36a12276b72a1f1f10	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\x3635fa1da3b90adbe2171f8b82b0c69150406cfa468dd1311c00fd9cecd701c29d50cf529af00cf8c361156a57ea2f41fe4409acfcd35a9c5aae558ff755650e	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
3	\\xc5a9d3b00e9bcaa9481888b452efe10de6703ceb74e88feed591c038aed1d78c	2	22000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\x47cf2ded2c283ddbf6560f4d46fc5ab392fbbd30beee28f02f7fe6017f9883eb2ef071562f2b59845a7e7c243b0138832346745e858a4d7ba66da3e197193507	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
4	\\x1d4cee3880ac818f40a19fe3598afa22dd89cd489330019925f05da33cc28247	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\x8bc93634eed797c61a2c4c099ac5c59a41c83ff64de5ff4a68bdc51496601ec298f70131f4d6d7d29a6e8fe6399340e2ddd82c5d0ea31ecf0bc187d21efa200a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
5	\\xc34ff75267df35338b8d2c056b52fb61b23a3235e5a14426ab6a9fa4877a1879	1	0	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\x08dda1bb31dc789ede97d17db1134c245ab5a641bbe810153adf6086b249414580fd38776a5283a2162f9a0f1029ca70b17ce00c69ac8ba2b18984dddf09b50a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
6	\\x8d734ece4bc6744ae2844e27432dfe2efc9f6c4f9471a03a2373201af59686c7	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\xff9cb1f9f0741405992110ad29c3c88bf52978e13d38e0f2d4526efd76ad55fdb4d16a99ac0a0654782911faf6f36ecbaa3200cd135a89961abe5831da118707	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
7	\\xa9f86a06586a4dbbfc81caa35ef61ac4fca38163a890d3135179037a1382d948	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\xacfb47f28441d70cfe3e462c83edc35e604f67684064a3b3516a8500a208ecf44359da0cc805c421f7231d2b3672d61f624e1b442ff1563aefac215c1c92320e	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
8	\\x116a86bb3fba1167d4634843e9dc5e099af16cc58804dcd649afda54502ef8c4	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\x45e99a83feb21744aa7c7a2d05746d86fed42b8ab1e386e8272a74cd9296b1d0b56ad4f81a64a508bee1588994ee65a6fb1ccc06cba4bacc51d3f9b3469d3b02	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
9	\\x7da5f0693fe546aace999b06053921e3a735d4c2dffb7d5a5e5d7e1ba9aedcbe	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\x741d3e8bcf26b3b44b8b0971e2ce500676f8d58a78733425e08d91bdf938e2edbe9971652927b398d02cbc488c31efbeac630cc5158a74fc4822e45b04bed40a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
10	\\x12185c045e46b1a53dc0145b6050e8897bb4e49fb4cf1a0e10586fb09d0126bf	0	10000000	1570364146000000	0	1570364206000000	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x607e7494ffcd36b75f44f571ace6b4fb9567d2c7eb7be7c6152a4ed4f9a721359f4b45d29b4fae345fd4adadd3d7f1cd056c221895e9855d4c27a34231b29525	\\xf264c9ed2ad813cbd0f4896c6c7a9212684d628d73fb0ba323081795ad64d223b69dca701b522809fd5ca907de66a2efc2d95354ef7d51e265c4e03049e49808	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"1BH3QN6WHFBBJ5TXN7YCFREVHXB11PCK0YWWH4FC4XH2NP304YVZN4V4P3MW2W3NYWSD2W7E9CF3M47K67ZQE4J74HGW6K9EEVZHSZG"}	f	f
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
1	contenttypes	0001_initial	2019-10-06 14:15:32.961807+02
2	auth	0001_initial	2019-10-06 14:15:32.990157+02
3	app	0001_initial	2019-10-06 14:15:33.026424+02
4	contenttypes	0002_remove_content_type_name	2019-10-06 14:15:33.049592+02
5	auth	0002_alter_permission_name_max_length	2019-10-06 14:15:33.053623+02
6	auth	0003_alter_user_email_max_length	2019-10-06 14:15:33.061245+02
7	auth	0004_alter_user_username_opts	2019-10-06 14:15:33.066397+02
8	auth	0005_alter_user_last_login_null	2019-10-06 14:15:33.071267+02
9	auth	0006_require_contenttypes_0002	2019-10-06 14:15:33.072138+02
10	auth	0007_alter_validators_add_error_messages	2019-10-06 14:15:33.076975+02
11	auth	0008_alter_user_username_max_length	2019-10-06 14:15:33.084371+02
12	auth	0009_alter_user_last_name_max_length	2019-10-06 14:15:33.091428+02
13	auth	0010_alter_group_name_max_length	2019-10-06 14:15:33.100852+02
14	auth	0011_update_proxy_permissions	2019-10-06 14:15:33.106738+02
15	sessions	0001_initial	2019-10-06 14:15:33.110323+02
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
\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xf937b9f577adb16055bfc651609c6100b6306a3042bdf2cecc774f2ae7b714cf2849da1a781d2dadf282c24631bf78bf64b26db6aad63de2f185982cd9c53101
\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x4d9587e15184832d149572a5cace3ee056c19a9406beb76ca735a4669938abfe69e2a7d7da199f11fdff1faa2a6579122658fee82a3dfab77a4b34134c016d08
\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x8b4d15e0188ed98d2ce62a64bf83df0e440ce035e34099b71411d014a6bd9302a3cf749db4e06ac73278aaa7db79b7d9c8809adaa60a523b62eb072e7aaf7400
\\x6a4cf66e551842067e2d8cf403249c887ac6b1c63faee015d1981820e74cbc87	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x604d2c6b5cf08483a2d63a577b7c2a616b3f058c8cb2b8f38f02f31007b597daa5f575a7259ace84f338fccc29ce11da13ca6fc0e4dc9f91c3818c3698fe850b
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x00914420cdcb96a2897321a3673a906c07c0d04a13f8ab36a12276b72a1f1f10	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233039383844304331464645393845374636373436343630324345434441353633364644314138333736414334333933453834363536333346344231344644333234413132463337394335354132453845353242353832424339463738463835443244453338384430354439413643444444363634464339364646463439413437343844444543464439443543424336353145414345433232373132334435443139373844373531304134434430394645454437453030333236313231373543354431364444324332303244363030323335453244314639333434413034414435324533444438303431433433393343313235444341383734453843344637393123290a2020290a20290a
\\xda37cdd2b6b9cf8313269a25ab96fd4d44b7172c52c506d8e6cf604e09c6f94b	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233232343930424133433139334631413343324444453135463442364443413845364342334538313744334134453733453341443537393838334333463343424643453937423035323130453436353834314341443632333733334138443030464433424243413332463441384536334446303032334637343135363841454332344338434644464242333341333143383841344244363837354632353532344643413244323934424135414135353743343132313537373241324236413731463146344343344534444646373931343739373237393744344339313445443431344232323035304237364134464630424632333730413635373945423442303323290a2020290a20290a
\\xc5a9d3b00e9bcaa9481888b452efe10de6703ceb74e88feed591c038aed1d78c	\\x9d9f7f2be804e12720e469a0267b5fb1b368bc52daf3f251ce908240698278473fe63e919ebba44f7d8cca4e379c49b3d453418821e309acb77d02cb3ebb92bc	\\x287369672d76616c200a2028727361200a2020287320233036394645353531373044463034334131344335363745414637323046343833364544353830343630353438433334414335323842373437384344314435343338384236433436313231413743363143323438353131353844314133424130373142413434363936384336453743424537364138393437354443393231413539444636394641344636383138453838314442434633353435364546373333384439334642334230383235444433354445443939354139384331453943333230453742453535453136353032354332344134313433414246324535313744423238423036423241423532363730313845333144314646423737373333303634464123290a2020290a20290a
\\x1d4cee3880ac818f40a19fe3598afa22dd89cd489330019925f05da33cc28247	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233938453433433142453136334634464344423437443638433946304435393638433342433146353943414333433844323633433938453543453139374630343230344235303346434244373536304541363032314244334539353434383442353734304639353135413439303332303941334433363733324535433639434341313238383546303732463138314634433130394530443943434543423136344545393746373439383934463833303531414546324334353535443834363342394133304243303438313731373531393230354430374634303135364134303739443245453541413133443336373244464130324437343039424536314639313923290a2020290a20290a
\\xc34ff75267df35338b8d2c056b52fb61b23a3235e5a14426ab6a9fa4877a1879	\\x49f2c0a8e108b64fd7ad4297b54e414852bb0a96f723cd0a6b18529db6e0cdda8910ed2d3b65bb4fea3e3a52a4d651dc1d6ae84c65e1b8e73e1fc6fc9e578e5d	\\x287369672d76616c200a2028727361200a2020287320233344393235433642373144374430423937303132303535453635323638313434363946344330444233434336424536343746443945324237303632373746463436353138444643303534353545453145383832424345303941343632433039463738443831374636384331373530373343424330303736414444364536313230453831373137363133453436364543383546333546453235413730423931433033334433343846394532323438324532363141464241363943463646303637353443394544303742364336413842313932343345314333313939414236304235433344363134463735433035343231383535393443454337393237323941393323290a2020290a20290a
\\xa9f86a06586a4dbbfc81caa35ef61ac4fca38163a890d3135179037a1382d948	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233939394645394645304336414335363438314439463337343643333634443743333230433638384641314235374441363331343036323930443036313237354645464131443441323741463236314332424632423635344139324635464342344238434446414544343742443345413836434535313343434545373530313034303236464332353232414643454446323430433031463137354437463341423245383636453630393034463134443536374645353433304537313345423938323044364434463539393544413441454132314130434441413344454546343032373946383843463533463237334644334346453044424635433242383633303423290a2020290a20290a
\\x7da5f0693fe546aace999b06053921e3a735d4c2dffb7d5a5e5d7e1ba9aedcbe	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233230353534323832393130423037424442313044303539363044384442453236314242303531393438373438423230333143373133363433314634413335364532393334443130354243463335314134304442353634334332464241353834463537464131424632383246414634363745373141424633413038323131313141424346383837363743343145433130444137434146464136413241383832413431304434443045384142453534334642463735423337393933433138383735314531433230324134393633424432433533423634383145413745363542433842464235464437394234314537323742314234434144354643334130324436323523290a2020290a20290a
\\x116a86bb3fba1167d4634843e9dc5e099af16cc58804dcd649afda54502ef8c4	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233941313237414536333136423043433541423736373033394535443031333036463935344535423837414144314331464544343936464537313034353239313431333032314331443035444244454239374234344131343635423443423037443946304443373932413841464645304530373541434644363838314439413644463241393146323436423445414242353739384241314133323642343343344232453733373435334435323332343937344635363932413044344241383146413731463230433937453634343034353045344334414544433442383843393830464539324234334242423236384632364436443945323932413537334136334423290a2020290a20290a
\\x8d734ece4bc6744ae2844e27432dfe2efc9f6c4f9471a03a2373201af59686c7	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233731433435453445463936324544463044353246333836333535413446433038324435433346394633334534423743343139303841343237353446364431453545433934353137363639453742454235453744323843413845384137453046383442414231444331383343413036323836413035324435444343393237373441303138333138413239353046364545303042393243443233444337454633304330323738373636414538444138393845394344333942393541444341323731304237394630423146304434344135333143384544443830323146363845424136443243343844433235363141303432303439334538413335353941434445313323290a2020290a20290a
\\x12185c045e46b1a53dc0145b6050e8897bb4e49fb4cf1a0e10586fb09d0126bf	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233439423632304644363945323646433030333931434538374642353635383038413930333538393744443843463744454343363931423346333335433131443130313934463843333345323644324636304235463143323431324146323444433734453837333944443634324345324533423346454443453738453541373333303142394545383045453246453337374638434341314636324434414433464539333045383143383242394446344641414334363439454542453846433736334637393435384245334132443234303232424238364435444232384134424631384243443835364236313131443341454443363446424435424446304442453123290a2020290a20290a
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.279-02E5SF8W9PQ5W	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3237392d30324535534638573950513557222c2274696d657374616d70223a222f446174652831353730333634313436292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353730343530353436292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224439364643564a4e33313130435a4844484b543036393457483158434443453637595145303545484b30433231535443514a3347227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a2243315a373935375a534d564245515434594e525453534e4d5a454150464d5037584458594648474e353937443959443734345453594a54355441444d5a42484d425a41415642454b545a5257543142433438433942544335424e36324638543236365339413938222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a223047543944485951444438585944595334393139355a514b46584d3157454d534d4546375734464b455757414358545643464b30222c226e6f6e6365223a2241385054434e54394e434d46464b59363152504854344235584651423833503844454e4e383134545939303742424d51424e3147227d	\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	1570364146000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\xda37cdd2b6b9cf8313269a25ab96fd4d44b7172c52c506d8e6cf604e09c6f94b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22473059545858435433513433414836324a3346344557315a35384d574e345054385756533435324b394734434233424d463738315353534744303054364657484d384445565633414e5237524a485246414e57395435383550414e4e4734515a4e414e534d3130222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x00914420cdcb96a2897321a3673a906c07c0d04a13f8ab36a12276b72a1f1f10	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a4333474e4456334e4b3759504e3335543334385141313857313154474b5a505638564d484a34324b445737355259434246514658423554435a5752485430544e48374e424a57584d595057444d4d34355257445a4b51513850563130423056354b5357363330222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\xc5a9d3b00e9bcaa9481888b452efe10de6703ceb74e88feed591c038aed1d78c	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224844523231315a464236585953575341454332333859333746544b4333584730375654544d34464e51364e5844484e48323850444d5a3256574150593841523843343947393933474a57585233334e42533657575142454d435846484759424837453334323347222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x1d4cee3880ac818f40a19fe3598afa22dd89cd489330019925f05da33cc28247	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2246424d4e35434551335939565a4e344e4e5239365651394a544e334d42544347334b4d4d513651475248454a4633584a3237545a305a574d354836514331333853544a3237334a42384a48355a5148515347505752585032444e4b38534b343651525345323130222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\xc34ff75267df35338b8d2c056b52fb61b23a3235e5a14426ab6a9fa4877a1879	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22454832544d34565457584a34475636324e3447394d31583438344e585a384430354252345647323836574d54454a4d4a33515a4e575942314b58453850394d585a5958384538465047594b57313730434848415732505a484d33354546354a3653543143433252222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x8d734ece4bc6744ae2844e27432dfe2efc9f6c4f9471a03a2373201af59686c7	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22445a46514d5243464638333231584d535a595a45424b3338314a565042325a353543514d36583839534b324e333957414237473450334a514e5833444e3446434e3546325230304e38395339395441534b5143474d4e434a563939475248374e4e4633304d3047222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\xa9f86a06586a4dbbfc81caa35ef61ac4fca38163a890d3135179037a1382d948	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2250353241513436425a4432425a4b39443239454752343634435a4d4e44585256474433593654595231423442375639425756465443344d4d4e47485038355331524736313656364b47504b3748324648544332483657434859475a42564e435458583035523252222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x12185c045e46b1a53dc0145b6050e8897bb4e49fb4cf1a0e10586fb09d0126bf	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2232333241584b39334252345359334341325033485a37525a504b5a4131503536345758444e3136334d435657324339414852574e4b394242324342345030574a473039484233394a3745575a3539424e4851504a45444542455938565047523159315a304a3038222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x7da5f0693fe546aace999b06053921e3a735d4c2dffb7d5a5e5d7e1ba9aedcbe	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225758305a394143434d33304b4d36483239564e523339374e4753375a323551595156363559595658534e303139454744354d4532424e545a383357544558575a56504e51333436415a5041444852393732375741575a583152344b5833375052535635594d3138222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\\x2b8d715b8d827e82a3370bef5724d3ab757b2e101dceece4e3fbcb9e039118dcbeb85946edbedad411dc411588bafb4cc8365d7dde27d73cd5a9a608e188f068	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x116a86bb3fba1167d4634843e9dc5e099af16cc58804dcd649afda54502ef8c4	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xa0fab49730cb586afd1941085d23e8b4ebc37123150e5eba464c2e8202eafcd9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22345a52453852584541414e5336314e594d4b504d4e5a5932304b39435a455259434e45395439354a323143354a4332545858453156345a34504252475757343737574443455a58445a333233575450575a51425748565a474e594e4635544e5634355331593147222c22707562223a224d33584239355347534443364e5a38533834343554385a38504b4e5736573933324d373558454a3639475138343051415a4b4347227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.279-02E5SF8W9PQ5W	\\x043496c7d76b51df37d9224292fef37f681e3a99a39e7e11f37738a6775b63e6	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3237392d30324535534638573950513557222c2274696d657374616d70223a222f446174652831353730333634313436292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353730343530353436292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224439364643564a4e33313130435a4844484b543036393457483158434443453637595145303545484b30433231535443514a3347227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a2243315a373935375a534d564245515434594e525453534e4d5a454150464d5037584458594648474e353937443959443734345453594a54355441444d5a42484d425a41415642454b545a5257543142433438433942544335424e36324638543236365339413938222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a223047543944485951444438585944595334393139355a514b46584d3157454d534d4546375734464b455757414358545643464b30227d	1570364146000000
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
1	\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	\\xc5a9d3b00e9bcaa9481888b452efe10de6703ceb74e88feed591c038aed1d78c	\\xec1769719895e7a96f84387027ec625483119e49b1dd9fa55841c5a3f4afb98d25344401c54b41f33f54f5b3a6f6731c073155a361c69a2d565a80b8ddbbbc0a	5	78000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	0	\\xebef25c4070e3665e87b07667968fef81d449748368f58dd5da9aee6971aca390257514ed8a3b0cc45256d17164816559c0742e24f6b654970033b011ea3f406	\\x532ed9878d385ee8b8a941f1f162faea46b65acef26bf76ab1260a459ca4d2c3016f5c7627d00377e6c3592fa99610ce328235ebab2dc112e2f4ef38558c17d9	\\x2e226438dd40afb42e968a5e31d2b0fa5bd433dc72959b5930124b9d91aedeb3fff5259639883b5c26da9ed3d4ffec0f6d50936323261ce570f1bcb1168ee90bf8591d319227e8f0fd0dfd1da0b02edb02bc33453c9e560d0f56485b58c7ebe31cd25727bfaa7d1ba8c0691cf928f1e8bda8cf098c559bff18fcc885b28802fc	\\xdab91dbb2d9b043cd03e0b27011ce3a3b3070f65b608390dd319517431e5ba3355bbf59d12ff700d562d64609e28bb5595a06b39e3539ce751731c66dfab2c55	\\x287369672d76616c200a2028727361200a2020287320234237393233314543433638463942304144433035313532354139313030464231444434383331434637354633343834373244363441363846383742443638423643453944333331353733304137313143464346443545334345453942334332453431363133394145433844334343383432464531393545453935343830344134324236314542414346353444313442423642414539384231394135363730313137303244383946394234344631323631463446453237353444333745394341464339413738374432413844443242304130323637333337444344464438383437333431323445433835453541343044363939464344433646323645453637363123290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	1	\\x5e58cbb63b5384afd69ec25e9451d35f1c57776569947ac611de92d2f971f79363ca5d38dd148dc3e6fa99c6507af1a9c871a8cc74c9298466ee82ab5e756e08	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x71e2490960e2bb042b39a31237136550a8adb44ac7c211b315f59f9e5fe15ca4826ae8fe6c6c83926c349f88f9d1cfa2cdcf643153b18bf2c803ce6b04998b8edb03b3bed4ce4047781d43fbc3d9b9933dc75a046b1de7dba18e0b3b6bbfdb3178e292744e3c25b7d286329b689e9e7b0645ed7f79bad1e837a1eebc4992f9d0	\\xfc7664e9f844ba604fc8c3a6aded895503b1be889a69145f3125516da880a40a31a83b5b4dbc51d6dd237a7a8e1c5405aaffa0b690b3b6af16a7faee4f59cb82	\\x287369672d76616c200a2028727361200a2020287320233845443642303834364236364244393643323331423432463830444343323832373633393438414531434434433435424641443935463043314341353741443932363133433332394443414231353534453843354531454531423632423742334343314232383032364142333444333243364632393735393233343235373230443538303537343544453935344133343642323739434330424132393230363639354235323637423241373135433436343738303335383243433630414130344546304139413539353133423336444332394337464234334134313433323733353033333642463043394232353537363531373834353345334438343337383223290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	2	\\xd2d05acd73065aad456ba285034ad32b7b64e6124a5a318aa8259733d9ce4b33b7a72ac9051dc5f4bd62d9fcc370856d130dbcd75d46def2a239626735efa707	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x4435cc67e08ed66210dfbba5b9beed7a96ca320af99ad567a3b2e54cf99f4aa2581b55eeb1d9fae469d3c0123c8e217c4966380f99e06227367aaa83e2f250e4bdbe9f9e618b57e1f1ab4df358efe4fe75652861a19d28b23199f576f952fbb4b58d77478dda5b495083d7350e5a9c7b88650d8a3c7ef9caab7c2c219184581e	\\xe033ca8de4b3594ab31e37375360db407d20bc5a34e2159dcdb220a8617e665fd1d5631783b7c59637467caa40bd2c22f5f5e959c62ae6b6cb41ea8ed8b03901	\\x287369672d76616c200a2028727361200a2020287320233234304332333636384146363639353346383145373542343531383942324439304331454638463642453030304145443142334539373431303638313532433238364243393633303233373043354233344646353445303645313435373543464344363244324143333136313530454541464632354437424138313438394143433943393346313235413236414236343632413141383931313635423239413841464433453344354236394141453734353346383939383035344131373035363337433833393446343441353543364131324134393239344542314646433044364435443834443735363446363541324630383345354232353838374646444523290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	3	\\x694a225224cc01a671a8631458ab09783f31b332dd1a52c377aa672ace30819783cf9b89d329528a3fa46f9c9bf90a165a2400f3ef38be62a47d9aae6cca870e	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x0412552ab027b191a6c13de53a8a714f27f38c53bf2666a82f9bb3c7afd1d9eaa389a0d553e72e6be46f6a364c3f0fa80f59957ee75cb00ca5ec1045993135364db47b7e337c24fc4bbeec36cb4a87a049acaa6391d28eefb0b0dd73dc953beafd5f76747f4d598f76157454b8448aab549acd2d9935cb3267ab4d47db60ca2b	\\x583bdac64534cb0b5dd8291b252e63d15c1d4e6ae0b436a06974349d463aabc7a34f942a3444f2697a5446adbe9291661d62ac4aef650ac45cf033cb1699bdaa	\\x287369672d76616c200a2028727361200a2020287320233930343033443030394645393942394542454535424643303232343232453834303932313531343144433736303544413537343939393139314539323739413536303539334243394142464244364143354338354234434146414138343546313342323742463432433632423544443737343345354235453641433236423642343739333842304132343930313844333443413245374133413138374639443235323031444345423934443843323042314541363037354443463846383133413332423238323637463233444442453544314344433839423133324334303338453936423835453232374538314244344142453331433533334443464235323223290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	4	\\x23e700ff5b948cc9a17fae9596b3e91dc17dfdc542d582f73cd975ac39d4aa84a477c38085641dbf4786b31d3772f1daafb9e908a73ae54c1df287055f144509	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x844844149d94f7bbb669d966b0453dc8778e829454de7993a10689375f0f41937db1a5cea8daa78a9b5b4801dbed54f699d76916a6593e069611c9080ada27b0f11148d45d0fa00ed2475301f21861424f59d79dbc8aacaa7814db2d92a613b2bf4488e7d1953943b3115142250881615d8fa18ed6664a28b5fd9bbe754a64aa	\\x04cafafdeaa71967185a8338ad6b6a704075c8b2f4aab478424d1b0031f7af3ef148ff2dd423f55ff81d8086e63d2877fee72485c73ff765b38541189024a0a1	\\x287369672d76616c200a2028727361200a2020287320233144313741314642314643303739423736324531364135323332344345374332413734413442363345324433423832343744453245434233453932323337333632443636393634363236434146343437414343383843444438344330383841394433434131393630373337424134334532444133433441334534413930383443314635373142363342354232464331394236463330443430433937433138363635443241434632334542323438343530343543303131414339353436444137384642464146353441363044333636323130374639424132453841383335384436304432374243413130443436463533414535354145463938304336383332324323290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	5	\\x2c07035f794d1f51c46dfc57516ee1499ab293b84165db9270fb6188f87287340e63e5cd559ad3fb081cba29123a914a1dc7727fbe2b76ec0adf72dd683f9f0d	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x0d4bcf71c10f6aece461519c33c98723e56652165c6dabc5b5f054d41813263322b7679835f24edb78d417f2e9c13c4b54533fd3c858f93789758df23ac95397dbfdee5f7e4659a94bfc10df208e50312698eea5a9d3fa0d13f2bdaa665d5ffc830b6345fdbc8b33ed4b03002204ef5b9fbf3787995aaf70a86cde382ba8bdc4	\\x277414e684269ae0aaba54c893afe5a138aef0bcfe30bcdc8b2fec4c61106b10f61fc87c5af14d5b83210b553514ac0b9bdcbb55fd0b9a6c238190105c1ee2a3	\\x287369672d76616c200a2028727361200a2020287320233834393541373531363237394434333345443035373741313046393742424634433231323633453043413241323130443630433242433346314632394633373541354446444638303236463536423231383636343832363637463034444331314344374337434332303144313642313438454336313934384334433239313038373243313841353930413246313732373437413032353937463232453043433844443435393843433142463033383842344432374543364243353243333832433633453231453243433942413638373941424244443432354232453530453932394546373036323944304533314145423445454335313246364434334335423223290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	6	\\x5a3e4db760cb9c3b06e074b0dbfd6e7bbecb72a98450e5c486f9a2946346455d0b9c4d2222f7b872273f2e92c25e2de46e3a9de5b24e49f847cfa9de06f98902	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x883438a4e0882a9d572a144ced0882e8776469ef0902d583ab3e30a2060768d32ee6256e8b942e2a994efcb65163d1fc77a103ac312cbd12cdbb636de15aa4a812928d2929d8ce73e4d7d4f01be93f246a70b30aa65c5c58f242f4502419e69149b8db80eac35aaf23e3a947a36d24dd45a1188d0d1de3091567efdb815fdd87	\\x06d8108d93dbfe9ad22501a2e70c4d0dead511bdc7a21bb5293293e106a8b090a40470ce541b262c5abe1dca13cf29ece601a2e8a5b5498acff6bce59dd9b328	\\x287369672d76616c200a2028727361200a2020287320233542353745354641313446384342354439394444413143463835384538424331464546374438363344413137464546323245424141334235323532383338384544434331434636394334413444384632313933323835393537453243353630324635463243363337333545334233463835323638414233433543304137303338453336453030433143413538374442463045424239414237343945344641464331373935323233343636394641373038364237344137374631414138443733444432323745364144323136324337414637384343454135453238373243374637454439313445414137343033423038364346393536424345373845453143353423290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	7	\\xae75b0a85245b237ee1578d2b98c143025833f42509efa7a2b7a6b10c501c897dae397e5fd3f6faf2c442f0cefb615f138fea216af1e102e655898082c7b710d	\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x9301e7ce8e96b7435e0885a4ce05ec9e63a67ab3802ab417f00ab2b314b9ae3ea94123ee4e12f21c033b3d5c35464704a782e1629138baa7671387adc534cfca7de814b06ea2be00265b7bf7586f7b58cf7d2ad437d1f7ae636f4268252ed03b4afdc41a40903ef91c3d7bdc2d062fa56802a7b96afa24523b95030e8af2af1d	\\x2fff82fadec8c3005d6101b02f89d5ea4a9692b7734978176ff689c8a22b9c950435163f4262185378367bc4025037c2be9275fba0b31330ab54eed85df044cb	\\x287369672d76616c200a2028727361200a2020287320233035364438373743313036373131383042344542393336374332383145443832373137363939433132424337463737394335423130354639394145374542363738344536353044463433324634443932323341363845373832453534444534303645324531353838413930453137444533324343463334334239373846383431373435433939434341323037413141363637324530353135333243343431313443333633414141363536384333384335333741324533463945423838394431304133363930413142413533393141353337423044424533303545304444324637443535314635343438323442343345353534373342333445343645333730353223290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	8	\\x3c38fe84d92bff38b1a25e656684b6a462b19088c440218c7f9bd5e25bd73cce1977705b448ce5eaf36ba90feec10309b05291d184f684baa753260cd39b8304	\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x129294307eeb34e4a46a99a8d4fcaa2c816e6022be385be3c6a403e78f7c6a5c8921051d8f6dcda4b104746a1e99916ba407e80ac9b425e00ffc15771a86fe6e18fa823666a826016b4bef614bf28b90a1a98332f78a2316fe5b6828f1b31c32e0cf938717b1dfd95ecba5f49ab7ff5a8e2aa0b0c4dae1f3640c2b44b848241e	\\x5ed49c50f3e2d9fc37f7a6bfefa7a885cb49998253addc36b458d2d2f803e94afb7d1c945cba4ae6e4de5dab2652aaf7c7ff373c8420f46ab8c6402c1fb4fd21	\\x287369672d76616c200a2028727361200a2020287320233431363131393631363436373837303744453732364545314333364643453238414330413231344341313645413234464639443632433833443845354638363941454532353639363941343146364631363336383734414331383832323836343944343042464439333543353833444530453838374443443337443944314335334641333344303041303643343244383145323543303344364431454344343635394430413043333131323230323534424242453144353936433138363539353441433646384337354343354638454333353934443638344246374245343941353736373739433536313044374632393841433637313035373542383037423323290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	9	\\xd7b3b5f5ef969ebe2976bedb1be3f7eb5b717df1c12a1768c505f4533e380e82b400a131e6d1f513b3a73494b683d3621601164447d2b952beee671141955e0c	\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x37b70488bbc4783e43312f441e6b5e7d945b7ea9c23282fb31e7f3279aa950ce3a81240db4df352e66ac445d1600d979b8281ffc22282db737ff1e351f439e0c63b622d0d7b40fde574792100d63f2bc159e608c786f73112326841c04c151231fe140a41963fd8ddd9a040a9140f9c994a7af170c6a4b171f219c1443ae4f75	\\xdba4df62da31842da54506f333ba2f71cb68442efe5ed5df75d717b562b545d743f2deaf73a119e707c2463fbdedb7d1670d93740b5c179fc976f4c23c2a0501	\\x287369672d76616c200a2028727361200a2020287320233330444241353531424246344631414241454636313739433035464131303444303745463632344335314643373731363036453731373946343930393532423231443938344430393033453833414636364633454343343034444544433744413933394442313843423534443841304438333644334641373037333145304543304432464238423437454232313037464136373942333045414237383237463833313943423732354533313542393138314531393946464345414136413238374231383036454630344246363144433439324133453136413337413835303030314230364536364134333939423732324636353739464433373838384442413923290a2020290a20290a
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	10	\\xf4a3b344fb9345436033071d76cbd2f8aa13e1c27cd4159ad3281e2913d43dc27765f03aa5644f22cb4666b84a7c364107c2721b207c618d2716884a21f2b50a	\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x0cddb8579d93ac9f72c70a01b6ab816113b68eab4151dceadcc8c08368b1611fb30e0e2ca46ae295c96eaf4ee1f4fa7198ddbe68e0311b36c7c0382249a16de8a717de142a88ac05eb4af734433363fa8dc3e6351f34a6f152b57b8322ba71228713802e1452c4d8ddf848b3296618bc35a24152edd1e5fc40879568f7233890	\\xb161a713297e3b9b95dad322617f2bfe1ce705ef9d902b111cdcda3128ac98e2889d9ecaaca68a6d80b8999c5539a37509c81cfe135d26bae0c08d65c0dc58cc	\\x287369672d76616c200a2028727361200a2020287320233639373732463745453732384137303444303743383433453441343131424645343839304445343130363242313045364233444539433633334145443546453630433530413436463939464636363838433437324543323445463032333234374345313645464642363837384438444134353843464339364445313537384438413835364433353145383532393633323835434338373846413936343137353143424236374535443243414435324446384330383633323244314642464243433230413343433845383931374339383742383032384345324638393133373942313637394639324633433435333741384638343045344344364436374545363223290a2020290a20290a
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x9bcb7e248eae036c5d5b0a5466c582453aa3f7cf82be540f61281f5212564ee13ca6f17fc0c2e3d9e5b783dcc503cc17d82433b298d9a4738b304466a7e41bc2	\\x23f5c7bf5d334743ac7e0f3e15ac9d6eff647ed971fd24e5f11779f4874dc44a	\\x8a14be3c68869e358fa8f43b78b78a2d2108e346dd4394d822042a3058a4eda86357764473f67306a223fd95c509708c3b46535f925467c4e136c3aafd9b7e10
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
\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	payto://x-taler-bank/localhost:8082/9	0	1000000	1572783343000000	1791116146000000
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
1	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x0000000000000002	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1570364143000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x6f34e0fb4927bc9c4363566434600abb9679e0777e2226af7886eaa05f8d7fb6fd08fdf29773e0ce24423cd71318c312ecc536163af5858e683357c5ca34b4ed	\\x9d9f7f2be804e12720e469a0267b5fb1b368bc52daf3f251ce908240698278473fe63e919ebba44f7d8cca4e379c49b3d453418821e309acb77d02cb3ebb92bc	\\x287369672d76616c200a2028727361200a2020287320233236333130423132374431373841464231443337433634413439434338453133413133423730424545313739414431323332384234313436373836324531344231323533434342353343373646324645363739463541333739374646323434363132334646413337303630344342434239454641443932374641463642463542374535443930303335434335324642363737324530453131313933334539353236303637363442313736464339443341393134424532313533444235313343354437374341463234384434334141304442303343454244464345304246454342323546383535383332373133413338334541393737304537443636353937343823290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\xf7a03b11c698568bf5556e9878f6393aea8b8815cfc113910accf8817d36082326155296bccabb210a73622011b5c5ccb770bae58fc373e512cdf8933769d108	1570364146000000	8	5000000
2	\\x5442099f8b6a2a8bbfeca818816cec49e0524a2d08fb1cb5bc8c86dfb5ac87570a81fb5f1e21ee8d773c7072cf5f00f349de7809b9261bf51274b646d4c9f025	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233038423731353546303836414133434346463134434245433146364530384237313236373042383431303246363339464544324244303746394443313443304331433835443944363135323639393638333945413735304637363943363130454443353135343438443733393145464132303933303841443242313135393043353131354643463535384333353943463945334646353731423031343131463538334139373139344537434539333636364642454444434636353236344634424230374431394338423234303236443533383038383843413646444235444344383542374231333039334232453035423336384246303434344531303436393023290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x53cc18e39e9522abb5093dd29657fcec91f07d38cc16c15b11502fd87acb5f45ea037d69982ef148b67ad4c4ed3bdf27ff1927a152662da4d07f2f966b977804	1570364146000000	0	11000000
3	\\xae9a8e98ca1a8be06f82f88322ff1c4df697799089980cd418ab011fb4ac921bc89db3a3c29b16bfdc5fbf5a99c1aec564d2ef63a937f50c1715ec4aa212fec2	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233535463639353234373639313537453741453837434245303934314339333641444135383441383043453131373135383432443835333542454438423044413439414243314235433935304346373745344236373233433434444432373231353843434130363644413546363843443442383744364430384538303246383841373532354146324141394336323642323737354233464235444334453332424238314332413235454542443038383531394631343634324538364446313436414443393937383531434138323241454639463935373732414641433744304233444531434339354438324435423131413132303935384545304144384135373223290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x2bc934236ed5ae0d0a49c4bb10487d96bbf877e5ad09c8076fcab6cb2a2a88daa011e507e6a1cb0b68fc555ad7ecc5b341178a8768f71c07ad04fe420e108205	1570364146000000	0	11000000
4	\\xb7804ab5bf8841a14255b4a4e396624641625296901ea9f5dde404cd0a4de4de65add19e8c4c20540d58fbd82ac79846037017e92fbe7487d3acf110dc218624	\\x49f2c0a8e108b64fd7ad4297b54e414852bb0a96f723cd0a6b18529db6e0cdda8910ed2d3b65bb4fea3e3a52a4d651dc1d6ae84c65e1b8e73e1fc6fc9e578e5d	\\x287369672d76616c200a2028727361200a2020287320234231433546454131463231354345303835324243324242443433453444443038373935304641374638384545364343344544304632463837354444323433323135423541414646333333393937454545363844373034443139353036433838353643383441353043353138453641343741373936444433423541323943363238383442354438443331374437303544434541433742344242313436453237314434394536413937354434434446434145333936303345324331364439334338333537423837343330333136453837324336413132423533453131314234393531414530393134334242433941393335414233333835453938313137433943303823290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\xa995b24eddd386927e017e37cbdc2dd39c6da77aff2b0e3a4543660a23dacc70bbe7dc4fad76dabea3640656daba469ebc01a88882a066c875ec22b4b2f3b501	1570364146000000	1	2000000
5	\\xafeca15205c858f6fc6ebd751a94477686e63b1fd3c8ef9700e816bc7bafe34a7e4df64423cdafb89c5533114455214b357ba3c58e0bcde52d02410bb5da060a	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233339323037463741454346463135323646413043363635363746364137303633363845393137304636334436333141424234394142334537334543303446313431354242463636413434324545423337433333393643343031323536304544374535363241384237323632413038424145324646423241353142334143334534463446363944394346453435443930423730454245374532454443333630333733463944363844454341314337463638463238423942443033364644323330394236333041454246394439464638313442384645363342303035393542304236443445354331383538333145393739463035394435454632373634413541463223290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x076dac598cee3844a2125b21b1b141d294353d8c0192cd8704c8fd87b8a8a042517be512c049d56e239faa2b68a78a81b3a6f22d2b025b65413316aab06beb0a	1570364146000000	0	11000000
6	\\x7f76a2bd07d56fd95ba0eba3a131a6680d45f4152e0653d43904b8189441035ac159bbe53083e0679443561c5c2d95a4e939aa09f7c8c08f2232824437daee1f	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233137453031463337323145463644443735464532334530333144384330443545374632313946423634303246424533443533383937313641384545383730434535384146384143324333363242433533324130314635353136333045354637433445363244463244453634314343333930313635433646303941453836413738423538344136333533453945433843464446353330313030363230414142364438303638353332364132304346374431454642443344454646324146413142344439343331394136313841313641353939363641454143354133433236374144333631454134373139303045303942373541333342333038303932323343323923290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x9b2cc0f3dfb87bbe62d79082194d23fda192dcb468bbce6f3edb2898d52ade3031b602795dc2e4ff4ae016c2bf6a8612de3fc3a0e1bf424a65d654ca830eca0c	1570364146000000	0	11000000
7	\\x0b552097f8f39e75eb5f04612ce5019bee5c1f91b07b4a25c94ec66c5c3adfedbd8beeaa292082d2d097d0fdbff7e297287e4af89228f1b1cc93515e59508018	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233333304542424644423132303330443536463236394431393938343944423738313535463431433733333741463636424637303437443342463930344246463744394238333046464331434534323142413030393042313541384339323245423635363633343441423443304343323738433939384638324446304143353042343732363541393444323945454636443130443941424631334542313339383046343245314130414444433333454130323830324141383846443330393931443335433833433639333337343939433345343131373333453433383834364142323630414133413235334439363537444534354331393833353931383730363723290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x806da758594401e3c306342ec58353a948d9d15e7f2246d587bc8e97f9b7f77c599f433a7c0b75d5b18eb9c825048bf0cef122710d668a5a6ea29c62a74cbc02	1570364146000000	0	11000000
8	\\x2b986cbe2aeae7a4aa70389c97fd454cc497c7d312dce59b8e88dfcc31267c31faa0a95bd224fb67e15d1e68afd264690f3c5b9f0572f084a8443d109a2a5e9f	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233531463337373444463830383030333130354346354233353233353938413332373130383046374241453337333542304341423235364545423134363930463632384632363038323334413331433132313043433235314237303538374145373134433843383834323944423232413746334642393742304438303931334137313136384532443839354533423737303633423946463643334238373330373546353841304237334543393438324433383732364143303039373535453536393746353142384346353245344432414344304638334446454545413636413745353837453030413246354430333743354537353835423833323631384242443023290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\xe14da0c129f3dd604f37d8ed352072e3918a76c5c955f3b75abe401c5d65718c6157a697c6e390dd52926cba44720a7f9f50b08131ca22f2bec3d73e835ce302	1570364146000000	0	11000000
9	\\x82e95ff594e06e1d8f17b27ef10b425466b6823a6b3b4ce60b22961dc34aa4f4e038c99a6db3864e5ff4f2f6257c49e6cb2df778681ca7950f141adcafb44ee7	\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x287369672d76616c200a2028727361200a2020287320233930363046303834323835433345423536344431414236313136393434344542343030324446313539433944333242324638324633423036343430443245353231463839383741353838363337304544423637353631373842423744303245414344454539433735314244433544324344314238353331454337373030354332444443443132383038363538383338414145383039444339433631413335444343343533363344414241433834343434414231343734454343393334423738413837424432323541373846433632364337304641343337394637384346443539393730354543433044453439444231373146333745413834424146413644413323290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\xee238fb99e709e4c00e6127d5373b58546913ab79550bbd89d5528fc71d401b85093eea1594027cd8bb014a604e910c8b594c74acd65a9cd498d51b2fa5b630c	1570364146000000	0	2000000
10	\\xbd633a05aa7871258294153907ec3b60325affb403bec1f684c75d27a347e097227836c1dc5b188e2f4aaffd9611a0cd4ee79be8f1af3a6433d6544992123fe3	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233530353030373330363030323234354246384537303837374431363744433932363645314544344135463541333332414639444137443133303741383837303237444642393544323042413344383942314237443146433145364246363544423243303643423146313134464439384344314632373441464441343642433032424138383632304132423730314537463944424634443845424545463936433245413035464238313730334641304339423938314537453733464245453431414631424532313438394543433932443333343537373938383031313942364434354343443530463833324543314637454242354434363332394144393533363623290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x5091f353431f3a39ea71814fadb596d0e86059e4b5de363c5ee1c278432161c388e1ec7b15f57af833de4967a808722b021c0d59f85e85fb07620ce5e2658e05	1570364146000000	0	11000000
11	\\x57ac9f9b1469c6992c112568c2d5dcb71c71c1988a9cba46fb1841070b46c243d7f20a216fd8eb3554d0d5dcf8c6c27b0d0ba5bd5d78b2955fcc3a60ac7bdc14	\\xb9c7462d85f7b5ec874bc24d35f8c71594a4d8a2bf535d8de554fcfaa088a9f1ea2e01602fde1f39e13d2b1869f97ae6ad63c209b3eef512525c54181c10e3a7	\\x287369672d76616c200a2028727361200a2020287320233642353737313835303238393234374646373045423337463039464538374641374538354134344141464542303533373835334238314637343245443237414344393733324246443539463432423146463344353436323937313231374332354434453739324244454643313633464639303744313336303632464242354333344142364545354430394442433141354637414534333339354330453741374237393046453746323237433943463535463638373233333339434334303546393938443245424346333541393045463246354633374441353339423634433136353932334330453432463036463632434545313831373043334137313845463323290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x0e7cd264882f417e9679f73858bed563025934a7b5bd72ebf7629659e78a331d4ad8ae2dce645173218800e9993decd062ca7bf2aeea155c979ad8bd9f200302	1570364146000000	0	11000000
12	\\xf3aef91e7dbd650e6c878a0fb638300cc1a0bcb8f0a41eaefc0938863d85d5da476ba74c62c612876bef1d7280865cad04b47e8a3fe5a38b393aca7964714483	\\x71b22327567c2f4b89da06474a8c4b878c78c15648ddbeadea29dd1914084e13530c8bf91e08c92a1648290d93d6d7018bb8339719ce7d1282fdb347caa193b9	\\x287369672d76616c200a2028727361200a2020287320233435443442423238313034373731363343464646434135453739413636394334353141304145393938453944383939304636443730334238443837334645423041314344374145353543414136454631324541333138334137353732344531384437303146334639364542414232393134393837334639323036364436454431443136304339304131444242353133444542393746464642464136353034373536423738423535323746453230414646303242363139333835434543443041333541304445383136423438374145443335303031454146313441324646303144303538374443413031353845314532463846464239383031423846463737444323290a2020290a20290a	\\x11b575e78380bd35ad2a88db0bb7cbcff7e6f8911b8f87c10548d5ddb1bd6fea	\\x8adb5054f9fcbbda48175be75aba8869e01587694d6458e38f1f8d64322307d83f97288b008d825e6518563453f0f8046d59a039ea10457079b76e170ae77908	1570364146000000	0	2000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 10, true);


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

