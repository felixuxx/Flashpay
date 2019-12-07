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
1	TESTKUDOS:100.00	Joining bonus	2019-12-07 21:32:30.023603+01	f	9	1
2	TESTKUDOS:10.00	PAWKC2SHBTVS19GJD776F9G0VVAY9GXJT17ERBD1WVPXYK3KAN70	2019-12-07 21:32:30.101726+01	f	2	9
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
\\x4a1b41095625c25cd32fa24f466e5bbb96b9eaa367de5feb0aeb320e18c72c58ea717abb8e667a95f8f9d96d8dccbddebb8dcd2dd77bc56614bd081dee4097a4	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabf82ed13d60d4552c8708e8412966da80d9bc5413e63d148fe9366ac263a6913d3424e2afbf95e22c3f181ff6b526135c6d5b0caec28df9fd1a4629281094c8	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a96d53031727122fe9f46226d368629459282aec3682bfc7cc69bb8a8d6f09d23fbfd120cec1506f0fb79de08dc783c4e755dee906683b7f1960b4d0d9160df	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f9cfc61778c6a0074fbc1b773efb0838aa0419097b1bf3882a22aeda776bcae93d59cb7180656b2a66875bb5cd73d82500e4b305d8300df70f314861bb1ced9	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe644fa873cb9111009969ece07d7eec691348806f68ff8c9e712c3b5b3c2c70b9c6720e97801e036561133c210c19c352e888cb4d942c161e107eff944ded346	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x25a79c4b2f0000618885dc26279e5874f10ead2611d52994529e9a648e0992b0db24d7009ca954e2299b868926a99b2c13448f2eea4f6b0276fa985caa0d3e66	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf99e2149afcd82b08d3bbf6b9ea347fab74c9280de94b604314c4051ba0b117af390b1019b83555a1dabc679a4960f4761680474da58dfbb405703ec443b825a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3cc62a0ec1763c510aec24954768f9af5fe5608e02737255346036e28d3a46ca3d3f2f1d2e44c967e47b7f948e8d831d210c06d316aa4bf657201ef19cfaa059	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8569800eb0f10c3b6d9aa4c13e210fcb06a810d0cca9388a80cff6db517fb1115376cf0b085fe84d3ebe50a32c3ac7f4fabd3571524dda061312eea74d2f388d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1988b3c782f009a695477da864a3bf830967a9d0bf295197b0f5d4a42a66a937de194fca8358233644d3671d912fe9cc4ae97ebc0085996b2492b326ceb746eb	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ef848a60e068b30cb0badcc4c6e03524bdcf8c6bf57c3a5ce94fb53dc4e27ed1e1e36f1f33e4aa686dfd769d2db19871e2f5284a8ccca8a31cb6a38bf7b965b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x92a16b837912dc67f36a96d6db7bbd298b2d9ddd765ff1f239d2b006debdd5435d0768017c957bc365540740aa3503ac20df1cf3d53051285238684692a47fe7	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc82d8dec450a7201570f26ba8cf8cd1d6a0a2ab9b91fa755658a868ed4a34d85a879e5abd95314618a48c61d3edf85e31c3b91b3067bd72c86fb7894693d8f2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b68bdc3f97c7fbebcd162661770f39bfc12829787dde110e978acaeb41fd5f5dcdc998b2fed5a5a31a83883ce231bced5cc43c7e36e96ecb186ae10bba812eb	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x651f231b870aa890b4439e70329010bb35d3b42c78a798a20ea0126c33cbf35e79496a62be37fbfdf0d59a44ce2a6657b61029a196fee2c74949f63af0ecb862	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa0c0d52b8e20970ed0af6664634dca79f4563ad8f3f8fdbb9bdd01d8a24908b91e53662a837ca78e7395c30d0efb25873c21aab995dbf170429ad9c16254450d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7eefa8eae8dc40c4ff6170b535d30bd5533ad0bb7f5804afc06e2fb38a75dd4d3f2786ee25ad07ce485460c5e94948a19ba9bee3db3ff36fae38018f3dae2541	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5f875d629bd24195f30663db450f4aaa4f85e1d95a3185d93bc5e53dbc98828a8d8194c67f2dfb7031e68bc3fbaed459263f21b3ae6d7b135dd013f22b281d1	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb2ebbbc1fdaa9d7587a4d5b8f688a3c4e43dfd376a9e2350213ffe6dfed7aaaa76a94012d0c0ceb3c444f27463d265a47988382759322ddd4840ef5b537e4fa	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad099a6f6870a6964f2c1d51aabc619e0b8c76f0a44b4a14c0f6d1996643d4595e4e83a3825145b30ad8adcb7d04eb43673670cb65308d96f07bd0a33c813618	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76213459087455078243dfbbabc1590482711a64c2cbfca676c639fb19ad286701f6b3ee794063f8a454139cc10e7600ed8d542917b90034292c99de4b1bfeaf	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86bfb94300f367d651a6a8fdfd395358fac5c756d65835667ccc3c6e3894870585127e4ff1e385879fc92b36eaac6e414bccaa9cc10d97fa140ca5094dd3fe50	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bb2033a790e16f7abbebb3eb17ade470579df8bed899100655fbca8b59231d73d6ec26d8167fd0ad002b37b2e6e6bbc7669d8b7d64ddbc3683299813f4b8703	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x25a07ad7db598f6f2ba12fe2986495fa1cf0876dcab951c6ceac56e29e57611a5cd8c4ad3326d7f2ebf43926a008a7debd9fd0b82b7890aef521d6dd0968f4f3	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7326cee8953b9b43c88d30b2c55119965594e7c1d867f2ec9984d2dea65523c52f8c64956726ded0afbf7234bec4a83fab3f9482244b3080a66efb091b35c867	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91fbaf7c74060cc62a2bedb32d2672e0291106e9b1ec786addd0d43cd861b5f93241dc06cf566c94662c2959a2347a35609cd46e56191d40bab4a29fd9944053	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c7e0f32ef4f5b9111dafd1ea36760c52c7bd999c2dbdc34ffd8b3508fc6d5585b870222ce8ba6cd856ea7aa2a277e4e4e37c1c7be8039448ca93c9c6915fd55	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfdbcc551274d09a8063a31e5d024956a029306da1eaf4e5135e83f095070cad0c6f19b5005e3c1f2efbca9409e0b76a729da9edaff2cb51f01bb9ba0a9fc2d31	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1472c50217dedf107b9fe8aa0ce988c4c6063be3d5a3407b16163d1711450f75bceacb05857dfa66bdf5549b276e04c24b59df8a3b4d38ee85dbf69f1e33834a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x00f8f96d0bb58d572ad0bb8bb250566fd1ea2d94513cd49aae49a08b0d44371c4157ce7cc1966b53add622e37e3c120db63b5771c9d89bb927fc774f99555529	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d79e733367679cdbce338b9a0b5fb5c1976e4e6c0c8bf01d927320b47403594ecf6a494f8d77e979c87625494658073cb8ca1cce6138a64422f812b516aa2e2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x821e1d3ad0b88d5ec88cc7dcacc53aa452dbb306f5c9f7ee53c4cc7e6a4da76e8ab9737bb614ec19d0dc73cfaa25b85a13e1bf0fa69ecd8801aae543c65abb7f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc6fb0bad1b4be71f4d1520fb4096476212175abda73127adac965fb8ea4249c3d20b1b4b1cdc77f62d4b7652e08fa24621a7672ef82b4c703e4d4fbeb2919b7e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3002207ec50f8d43f76208a1a5d1bb5457b75297ccb2364e39150bf14a1a38fcd30a7ec3e428366c8fde566119fcb4ae56a241acf1262b3fa4a6407aa1edee17	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x18a36a8f1de46d0ea5ac63e55b4ce6915e7c792f48f76aba46b65810342899cbe9bc0d46e5409bad6c88e8566cc308383940cadbfedbec2db1fdfdf696b483fa	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xede80dc88dd843e9defe97134d1596d1ec0a1a12debf9f222b342ed47804f986de7afbff441c26d2c83d9eb14d5b9c312ad114dfbcc47b4b991b5df29590d2f7	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0f8207e54fa6d92ed73d2238cce0a1ead4665bd6497a6c32d49fe19a835964ed81d6b76f84a57eedf0166b31135e392453a7ec2794d71f1056a26b2a6d2b4147	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3d9e8747b44b0e417018199780c43653a645f147c42f6f48ddb6fb33b13b0e95ea34363c7a2296e1bd1615bdf1ecd15fba42d9eb2dbba3d6fbbb30bc972af603	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71be8d21021e63b8b211f15d3b7b2fe6db5b85bb6c280d498dd930823892dcef8d9cd47f0a1fbfad0bfa502b600b70d1e21f6f195acb632453acbb43a9ed215f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdc3cd37afa5ac757125de279649feb12e1d5cffa5a012db4bf231e9f57bc8596c65953142c615d05b0a8c4532cf83f6bf96e4dbb3eba3bd199fdea33c4d547d0	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x87f1c2110d24fabab29c8652d09738bee78ab779e06875ad5e3f45285414c7b2746cf5d3e1400f292ee059531981bb3bab03d811e692dd23eaf6073ef546024a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x047eca666ca7a4d1876d87e99de07a3e9efeee00bef8442be5f427b031e943f27033a80806afe62b898e94d8e6bfc32e1e53da317efedc12374fc57954dc88f6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd630dadf854cb0e668519fea4b5f484924b7cb726ccdaa217e571f7342ffe1c93060fd17801d4b97321825d3557af601c2a2b39ae2a86aa63e72f67f291d0a38	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x981c5be59342b0ca2b370fcafc4e4cce4fea85e676ee6edaecba2a18414609386c1a169dea197bd6e1408d8401470aa09c95469428f325fa44ddad189ecfbc60	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe34855ab4deb1cd42b304cc7264a63c42d247ec00ba8f3beb427ca9b18ec33a952faf612b58be16ddb7c4015e0a614da8bc86d40d4aefe640cda3912dbbb863a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe49948121f2f64412304f7e405dec623d96579137b18a21aae82e7cc1015a10bf6bf4b86d0e21c4b28298a6c349ae9ded3d5f224301975b8bbd4a39e62bf90a6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcbc8dc8471762c69ca965b37769614715acbedae817bfe3cb23a524310e632c9e64a8742ce50057a49ec48d7faae6b7256f7e45603ca3c529ce0db61e807c8e8	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb4884a1899c4c5e74f20205faf5f4e8ba33c3f63b2618badef7f84d7693f7d38d2ee06e26deceb93388e1464323b7e129f2ae69ea1fb88c5492a8fd75ac56b55	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x25bf4e424f7bfe7a8fb6a2241e2542b3d7cae878e38d743723e21fbfec80a2c42d86522ac90654720397b6b0755ac881587b183005f4ff4eea89319885d3e24a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x572e92fddb0bc2a0077db76c0b22df25478044eb3f040b0e6e2f7fced9e07d891b7704c860180489cf0516a8c7f8762a3ccc6ea6c5378cf68658584bc554f84e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf141c106a3a3fcee4adc1e6d3fc88002f344588b75d5aba28fcc5c0d2d9f774cd3e51d0bfe8bfd7ef1f8dfd659a0eafd9b3b8a0c51f3bebd78623f0792d4b103	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfebaa5056868ffc755e58dfb80ce5d97b4dbe5a4303454275d34c88990fccdb4599ed51e22bc7caa9c906a0504de33db95fc829d95975228b49f1d3910ab81b9	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4a6a3394b1acb30d6355913826bb1a005ebf67fe2675c3e3f96790bd5490c93de3f24c1f35ddbfe4e71eea407681325bde9c571f81250a8feb8d93a17297fe5e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x83a68ac0a9a7452bb7be667d23c1b892732c796c6593d8aca3145d3f634d7783401183c8f0960de48775ded3a29798229fe8c97a91582205a8acc66004a6fd1c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x42f055ff44e14aa765f38e43ee4b6f0a21ac0ae31d11e986eef674851e36e7827c707c98f5c267efda85dd0e097b26f0f71bbf62ba3d6aadfb5dc35fe8ca23fa	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4efc8252fd96a731dd0825da93839dd1ac07323785a3bbc254ac08f09ee2623cd345e70828ab46e8906bbc1050a425ce04e3fff078f67abca967e0f8ca98302d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfcd4f8275b37da977ea5da4bfa8b5aeb8c111c9c17e0fd4f215567b1397991d799b89705c6cc6594dd21c971d49af514cc1c1f1ef2610965674c22c26c7d974b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9ab6455ce24ed68e97c4c71bd2876225dab4ae2dd93770dbae2138b62448ab9f4b0e26f815afe6b672f923163960f1c485dacc6b5424eca48ac05c3e6baaeb32	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x395bc325e29b043bdf7cb7991fdb4f0042a63973fd4355120b53c697400717299601911b9b31eeab9efcf4841c4c27e6796cbf18081bc4c20ee0ebfb2e15d544	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x85f2967e8bfb36db7d45c3ba0e34df15fc1e4e06b1f57907128a1d74784a9dffd3576c4db472e4b1dd622dc61402b41e754e598af139cc3537f6c3672e1111ac	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd73f4914d733cdb38be9a2ec55236b5258999ae465b812e09ea45351fd7ab3dc764aed99c4621450af9232fa65994011739fbe15ad308898f2085a4b3e111750	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb2a0f94568b8d5e6c44e289acb8e2a202a4cb4ca17a3254c001b2e0f37cc99e17baac83bea020b3f0f838677ab9c059214492ff03066a94188065f8d25c57fe7	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x028acb7568faf892756feaf7bb03851171e9bb6b7673fbcb61b518087bda57a94a46cdf83be3c87d535c066533f3237fdd8de61520abd233acb362f6f611647b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe1a0ab7fed353a2644c0f37f3f3bfa94b7dd898912ea521b6c677fdb21dc1c7c61e30f26cea4bfe9890f6362888d79e364d6350a388643a3408503727659f22b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x415318966cbc6e38fc27f002fd306d699c431b514f032d53aeaf20bf1b7c69146048d4da88c45de580a0e25950f6ea8abdf073ea0d27bb73e57a6432b59bb287	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x33bd72da24715ea9effc471ad85364a58a4e189477560fc964910a1cda9bd0e7cdb1afa49515f7142371e36f933228d931097d14865ec2c995c2ddecdd77ed22	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf21514d121046e9bc7f992c25f16475c5955222aba3063a134226f5526980e26e271e77c6001102e360cb4beba80b322426cce152cb57371444f368e92fda4a5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x622a35ab53d1e74953e65242e9af57d6b5e2c4ac8e9248c346396b6fb7088554ab109336027b01ba1fae50f96318f0fdb36690cc0698b6b9b05037d14eb06c82	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f0e72c7b9d1ba304cdf0722e2881e9365c05250bb20a9d78f9a9e3c5ed14f23dca8233714cdb16f56557d18ad4ee2272b594ba654e27176e51a43cca2919ed3	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32f96de50950156d7a05ee31101dc082a6d401b2ea93e05b5ae83205531bed49962a41d443f57cc35262b9eded861261084ca6d71c82a1b72e76759ba8e9c08e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b00c23bb5f7cdf4a3d40ff98e6f3998c86becb722636c10664abf4a885e9e5a30cf3986b01547a98982d2f07106a18eb65f9a77926c76b7b1e25eaa7f8b8fc4	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2f4f3609dff9d9198030d462fba9063063e69654fcd1662428aeb5075376056c0d7f424c1c13b543657b56ba332d4931f3849cccdd11ca297e70208324d7d1e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde5b7d9df91c2ed0a3f679e6d1f6b539ff4b64b40dfa6bff73411cddf4577b8da2c4fdc7ef9fd441c8f6dc1ff1d5ed57dbfe45eb85120d9da65eb9b2e8ea59d2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x97ff3d25baef458d8a1de3e3d6eaad637814b66eb79284fc4bd71a82ac808e994cae4964544db67ff67b6c3d5312a1a712d717c8dc5d5fbf649524dfee924cdc	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91af0459014499b8a979a32fe6d88d10a46bc9707136eed1d8ab8a031a8ca2f42c38cb2044eb14b6a48e0747c458ad3c5a7e1f7084eb3e4396665f5c90bd5586	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7439c62434f18bc02db354f87df6de48bfea84478c5425579045e11ce6631cbb5dc0ca0546dca84c7289026877317070670639c7ad677b87e38d59eca0c36bd2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1fdc1d01b387cb90b7939beedec3bc7633eedf8531bc97ce012c06def481d50492d233f74b1c7cf9c51d13bbd2031126db057267eeba4b9dbf564786adb6e6da	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8959aad988af1d58a69e77d25a1c82a62d213764009880a53d3e1dd6793f6ec740955bf2c30e8d0727644edba585e15ce1581aa9029f6488cf83aa0e07bdd460	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x880817b41eb47cd1f1ea161ff0e0f4569a19f2c500db4acd29f517014bdc8f24b8fcd82fc874e82beb35082919b468e8e47506028f5ecb1c9c2a344df9dbe848	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2af33ed28166eeacd9f99ffc7f0c594b3d7ddffedbf1e33b448a99032b2f9e8210e207dbf09e8745725f95832a60afbd3c8c84546b697e9ae3230bd8540320f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x255e4e3f30d13ee90d56e97e311795ef82f61a44b3013734c9a7f411b23a89a30dd43607522ca12a63ee772c3aa1df45da9157b1073ec31bbf6897f203cf7cd6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x03d886e7c4c906d033a046f9d245a8e08f1df7f18812a2cd1f21c69bd2ca1a157e5ae164e0cf69144febf0efcd68c52bda066193014af8623b1cc9ad9569dc71	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x393c6f0d8f81b6f4d7be1694a7241df90c4050a82d6200b7482cc25bd0369a2362b3623fb1a194f635e15cc7fa1d3dda97d4b51954115ddf2e596d14a2042d2b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5751f7daa2cf741f0cfb49eedcb043b0c21676cd3f249a5572152c463f1393da99322facec8e57eed1a29630801205f43184abb02a5f690fbe7b46706d6513e5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f095219ee769eefc32e25420611b1cba787f2a9999b2f848a57ea5afce0f9c2663ad0d4d037a3456230b4c4795e0f9172ba30e2df1c5f1142d2058a4babc275	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a23da6ca12c28d0cb270b47cef08c3fbfcff2feefceb2d1436d97f2f31370186a00c4bd151dba7aa03625213d92c98c8fc76a5d1d040d5587fc95f920b67d2c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x99ed7d3e25aba2323fcad69ad9cd5c8337c8359230b131cafc05f54b7b4be5348987dc2098d479b54f6c6531631fe7862cdab698c6549e94b0e4beccd853c8d5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa99aac984c406c8e1cbf8fd198bf3c39e64cd4ed585da2c118ca4fbc82305fd129adbd1f299816c764ef3f14e53e3a9b711549fd43871df3e665ddb55acab8f5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0944a3f20800e62fb89c1fb3cdcd053157d045f3ea0c0d3b8edecee66c54f4ec2855f9975c83cbcd0fafe6015ce10136e3039d46f6f1fa22faf1a233d3aa70f1	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf09bdfa5ea3f867d25575fb5177e18cea897e29575db571758ae3cce217ae5f8da5ae5ba556ab158cc345fb545f4387b0efb824d395daf8a47cdb319bcdef5ac	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd88736cc28a1ec843d2846d728edf945bc0de35a81e79c3474b068966eb886454fc051949c6b581c74a1edea89e5a7c70f6abaafc27ac98bb6aabbbb373f025	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d2ac8dc2539b9e8418c083135c8e160578ea53b4c5f398635426e1fa6044998ca4019525366bf84555f5dc32287929cd12f5a49ee4cc8b3a97e0868cf3746dc	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa60e118087f0768e17e4a6e55c23ab93219315c97de8461e283322c620ee87f6928e713e192aa06f3321c926bb305ca919f1b3c85f4597bacaf29878c4c57563	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2ae8f1a8f90a7aa404e1e98276e6c75eb6d9c8f26c7bbbfa88fbd9fd95f8e5197ec1f2e1a1fb06de24141647a1273d91d8e38a5c817872c18e19495775810bdb	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33d09e3b46587f4940231794e38fb3308816c2e85af6522f699000394bcf70291e227c3a564fa60d91b428d2ec3953ff02f96823fabe3d0e5060801748c2bd6f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x676de4d4ced0616452a9d458931f0da2785e959d89dc7b1434e6c8e4f01c8efc8c4ad09faae59ee569e626d930f5e0e561ff4e8eb0b7378f447ab5fb05172971	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bb1b3ea97df3a06053b8deec4f6fb72fae0da942466b1fdd75a11aabd2a5c795dffa057ebc9295974091402d80c76b5b730bf9556fd60d9a4ffda8606699349	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xacdafe25c7a935eb968ec2f90abf21c41391b70bc3a33616892592f517173e9342abb7ffaa1301fe61417b5c55c7aeb2144d76a84e8eabb58463c60a50e17538	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x744cd8a567b7051c4e94fbb1a8b1881cebb6b890dceb7910a3ede3159ecf1fefb7705a3d9a9287b737689510b8b2f09234bf5674c99f63d6c69e34537169ddce	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53614c144bc850a70f4a20dd2d2787018ab86741838d33a4133f050d6012b9bb41bb6d4ded3f6f5101785ad1397897cc3c395e50702ed28337ce96208fa504f6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x51ead506a3af73a755cf32f8409154a7ea014d7f22c9d02731c78d9cf27176b40ad07ac4514b929d8d6ce1dfe2a6826dd761affbbf8daf90cc30761e7c2889e9	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf624ce112bf9343023f18eced827b10eb011c4027234d3edc68a82d77cab2fb9c22d3049a7497b7d649fe941567195f4969ccc15e88bbdba7236cd9477b38b57	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8daf780a3fcf96ae1b215b55f51636baeab09db168ae0aac6c8d9b04426af0d9dcd04e507e117885994811a802cc233ff930f6528e20793e6f8d13fd32a61780	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde111a3bf87b0e4030b5a20b4e90fef2e2c72039296a1ce4e9ec2ed1c0aecbea2144c7c745e983f3a8bb9a17a99463cba86d38ea5ae53cd291bb9fd2a991475f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf91db1d09666ded494f1469dacd3c9ca9d8baae61b2181881f468ea3986962886da4b54005efd579a3e9844515292ac7825050f0e6aa1df2cd35068bed146a2a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x81e00d1a5cd328bbd659713544652e8c1bd1028e38c4929ed0d0c5a50e9c9ea7903c81bce24322eae7426f8bbe2015039c210a630a7bc7492ce319dc8abebdd8	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd2226832e0b1f3382cce3d9350b68b4d659612143e95b843b6d33a4d57f89f8162e1c9764894b0228dc9c475c0526c6b3c88bb68cd28c5f7acbee4d859b4278a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7952aa3f0839990b20d8809ba4fda0ef1aea25cb901588965608be244e5d5417a12d624859a9d3a47c627e42102f2f5a9b4f9644d7dabc480dd5d32ce755c296	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe65933583984423738c25ac946e15b8fd1ec500687f15c7079f347434af2e3825b7fc01cf499905f3b7de1792fc37fd9004f7ac1925877e86dc2d26c41c16aed	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae10dc7037cf92d86014fd1b2b543d7d5866ef7d32cdc64bb129c7422c52edf3c9ef6be538773b2eebd640c4a127b792648116f9b9d2442074ca7688768d3df4	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6dda0095880cc8bc74c33603538ee3172539b5d7eb79707a50569c3476638ccd622c91b10fcd4c35cacfef06c55ab2d26118dcc519f8efaa36e7c3fa75f7e056	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3f14d7482a30d3b34d2065bb56e3d15e9269cbd2a2d73f6997ed81b1283d5ea39dc6826235b87d78e9ce10f8c8c20e815ffcd48067ad9218236b4ef18ac6bc9	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb29e46c0071b777d76a4442f030af34257db51c43cd9ac5429e4b1a743456707bc8f2fda5ad8b8027d9705c7be5fef9c7091eebd69cd6cd5e1d1de486c06bfba	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa0715e3427dfa118a5b2303042f83a836ecf60375f913f2c51934ce2dcd1d084b95c27e410da8fabdac638e9fd680a94b08d0a40945cc6b32254b3d0ef8d750c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa000bfe14dcf9e152a3479d10c2a5d05abcb5b73f2297781a4a9c5f6b8d331d210bbd4c4497bb38e9d1d34ecec79fbe6c6f8a7a093bd24c9528b573b2eca1930	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa696a1b8d2c81495a1cbd531025cac9e7a4383bef8500b88d6ee07c21eb8f3c202a7ea0063b73eac78203c958eee46228e1852fe049468f5edc1286d46a5a0a5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9dbe49ac2c2130fcba1c3f7aad4c2b6f3a8ffdb09bc0c37fed4c2133c75a4b22e20c5633754229233b3539f3b3e6f3c5af731511560fb15d64240ea1df0a4c9a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x70111aff981fead6f8ba088aeee80891fcd3afa1206e676dff5dd1d66933be181f51e46f52188bd79eb2e92474a941e2aea8510495cf66647c143c5a2ede872c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x702ac269605decdf0884da96b5285a3ce5f4b92e90dbe1c2e038ca5ded8566c89e30d42a3d5650371a8d10d99437e74ac306cb20009b2b2357bb5e4e16b9c43c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbdb886f402edfd24e9dd701afef5db610b0e5cdcd89e56e871bc2f3f29e3ba68d007cc3ef978d5ad9705bd52cf1a7afac8d2cc0b5edb6f6047b4c4eda213e4a6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa438905fb4eb92fc40fd6e7adbc3b9abb58e80dc73f4ca6577a0e44eeaef68ec3491802346ae14d1c2d4586565ca858e92b364890aa7c807224e8cace56fdcff	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x782dc3e6ee18ad28409e3b7f59ea8a21b4bc56e4635bf8dca586469448341f652af948a5adaaf228204cfd6eeab6c6d3e13274ce49b0541d15efbbe0ea36206e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x063219493e91f8d5501c699295ffe70ef39759a91c250bccb4b86d0bf7b20a53b41f52f9ba09705548b6d2ed501104b1186de9ea9d9a521579b273dfe4f4a1ef	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3b3d419bec84eaf941223a0abfe26e9d40a1a284e3fd31bf25cade777a140767ebc5302a807d9116b668ca77481b6c727ab532d54898dc8ad2dd27274b3fe8ae	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x96b23dbcc50b8af78f26e4c2f6767da94531186599151254509144d49fd433f146925302b2544ed492a9819b6f43e8889dd30a58a513682f343d24d98878051f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x454e7b90295b04f1e6ce03b7fba1b76453ffaf781d24e0b7584689e7dae9243bb3545676fefdc10a6a54313ed8f8b77b999658a573860728abf1529a4eb1f4cf	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c1ce78e2f0856e235290b28f7c3e00f40c4e8e958d446b5f478ff11bc48f9de7371df8aebb11e8ec6416fb35f41d2927e00e1340d7532da82cab7e0863d8743	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa15b260f5b4eb75e852d4e56a5916fc904511ba503295a768dae2922b029b51231341efa109982fc737f1695a683149fd1581d09a0bf61b677c7b11e58ff1f71	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbede6e2059ecf95855ce78be09ef5e84e5594447632007555d86054fbf1b3fb4b620a93e21abf45a85ee73db827ff8d65b1b0faa30011eeae07575af4c828229	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcc0df8dccbcdf5aa054be5f2b5d3bfe3c8e346bbe79ea2ab13bc270483a1c4857476d4a348d317aa27b2b9bed920378e6a5b1c464068e5e76382619f4316f711	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0b960d343d0da927c2fe2406eef0185e4ef5bc8775a0e720c919bd0a23ec7034ef73f8e7bc76826909f2875f992f154ebbb2e834433a7c1d7c5e613fbfa9740d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2bdbb5eb39044d59354e66183dce145430a84ca6eb4a86a05ffd4320324555e2e97f999ff9e89b19f4cc0522f7e6926043ef654c0b23278362e48fe8b52a7801	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa06ade8eac05664ae4b3d8ac5775b4efbbb4520cccdbb5b75d172e26d718603095ab2c33f046953127e23a3d1f1b071db864871b5ff3f89c27ed16aef96ea2f3	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x22841df4c01d3e745e26bab5e05a90de308767a4d728d748954beeb93aaa8e70af96624d4b507c79ee194f519816b30b40b4d363541d34e44f09024e4a99240f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfe29f81e7464847c61465108f2ba328d41709d6dab5df9d49d9cc5927ea121cb5b3fda7139ee521cfc919b8347b1fdcb0043dffb2dc45d9b91c5ce903ccdafe8	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x54cca7796bae348d1ec216927b94db482b5aab18b09eb433c8047a088c75727139591c54ca1d1c273f72840241f7ab543ce230dc748d671250fe0121bea93996	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe51d2b754308e414e37e17cfd48c9e8b424cef77803e45524b156cfda21d95f3143fe36e47d7184951839223b5d557b15631cb7d56aa4a14ef6ac226c570a159	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9aff539fef9bc9360f6eb44bb13389e4f97880f6690a7c210488e47de898b143de5417a33c21bbba5dd0db734515ed81034b93b7934b9f339129494c2196debf	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x548de84e0d8711c4f6e5a3f138926b96f759544b315f86dd9c246dc366f8147fb9d35fc9ef89c43416603d31c9df102a228a2e86c2f865b0daf571d3c4b4df89	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x145110cd55a05f8f4713425a8a085aec698c43b3fdeec80ba7f58dd827ee6a4a57999ab258ad78424e7b417bec9d0cd79ff50308e0778651339d0ef1d38d36b5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x163fd01e3ca8446ae68a6bb8dc60d1fa06bbe94ea4cbabbea56f0bf97f5c62923aefe0fbad9fa72aca49daf64e8fc02101b0815aa0a2142931a78f3264ed7a77	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4770f5fbe7fefc62117ac0d6538aa916083fd8546f7abe44d7f5ee5f7b417026fda071dd5b2b68d8a0cefb9f0609923bc5376576a510603dbc56d257be249d9c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ae1a4cc59ec9df2ee4ba2cae2c68690adb40f290bd494baf0c5ac3df0b88a2f7ab2cb25af514b6bce1e24ee33da758829336aed698e27e8602c677181399684	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x189873bbd7d0f6d3644ef941998e6c2cf53c16395d0f6a957970f48f0bf4d9813a839fb8f26feb52059589a0c2d4588c500968a8a117666faec817b23b7661d2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x37e0a955d07df46aef52020cfee5e850b6808e6b359fa2d8f813de95181f50a2058473aa822312145bda7105ae8b0343030e67ce6ed1fe6cfdaf4613011f88a7	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x90084d2a512a3baf724208340b716def35df4a9132e27ffd82a52bd2594973d8878ff2f06ddd36e33e0ee4feb2da3f47e742b082d5e328584a988270c98693e5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd8ec227a844339002e115796ff462982c7b67b1e1a9cc8c87e399fb3f5a8b23911b5361ede4f891978cdb71c8ac29623d2195522ef0e1140ca588d8fe989967e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x362ed673ada8efafc135f71f1e799d1cf24514c963485e5685fe02355167a0520e7ad04c0cedc33d04857d8d6e804f764c987fba77962d76a8cc7d3af9bcb00e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x74265e4322ba986db25d58a5411b6359fd5aebdb9c7e90f24d44d8669395939bcb4e5aecf6021e3ca240e003d0bf52fd48f767a059e012739543f99a2e56ea35	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3ecdf86947868e71c1420f6ac9819ed02b460f85061515574c20b6d126f81c8fb09efe16bfac5fead4215398102535f46b7d8cf970d6290e6bf9afb066676179	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5ef7229e9a0d6a4b3e29c368d682e7c9c1174e2e0ea67dadf920a6eb7976ee36b968c7a26015b0fa2b575a52bdb3ea325dca3207b60f6c5dc340d6222e791d0f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7185539d3b0d5976b4ea3b49314c7aba0a9e8c00eb83408824e7ef5aa02beeba8071985816bdb7e6066ee6c221410be272910940e5efabbdc05528c8a149c172	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6fb8d99518ea478045944f4646a1bb58ad516213f5b99b2b6d47fa2301c00d62ba192121fad43db65d0b34bc9731a3fb2b0adba8bd4b84ff43188f6938e66908	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2bc048fea884849859e972be1aa926eec6522f1ca442976ec52a7377a8a7d6f0adf8e29930d67e4a82dc75847d4a93fd1e6a7f022fc1440bd3056476d815c8d3	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe771e17c02d1cbf4d3adbb7643cf21fe9be8e8daff5f77624add94c45e18f48f5ec6bcd47b0916d75c574b42d6d7c208b497f32a984e180fbec37cbbf3729e79	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf457c54bf83ab7a6c49334d415e4231631095a04f03c0c43ef7b2222ff34faca57c2c5b9c8f39cb422321d1ecfcb4cea8b707ed8f7e200855b1bd63c643e25f3	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe88e46bcb25126652b1b624004876e1ad3923067c5b3d30fc5efc8216922973a1b4fcdb4908f9dab6daba7926a24fa31e9d5e8aea0214491a0939b7277db93c7	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3f134ed3d36d77bdd627fe0f3a3f6625be65646877ebc6f37576334522ca98cc10ec52ff6d24460a56d170f9d1aaeaddc86469a158eec26e80dcfd93e9ca7291	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa086ef9abbdb7abc0d5e6cb117659ba6e69c7fa05d93a1e90ba640266818d70fa48b525a541965a038fa5f55a53c146fe7e3565217a8fd6330f002d3563d75f5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd05920a8096ff2e08866d957e33d254ce5fe47f1bf28a4ee772135713511e8620e93332796167f48c99ceec9a3ddfcfd53bc210a9a64ae5468c8cc9129a0f709	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb6cb36ea458e70045ec88dde72a148e7a30685a42490173272be172b115476e5ad7d99c0f3b21178514ac6362e683d05894d1956040f31ac88c7a6d9166f40a0	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ba4ea4976833adbb07a18ff53772911a302484ed3cf9f4dff17ed8303ed48d2b146fb36f160b7937cdf547da7cf17f8e8873072e082233dcfdffaec7380820a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x642820e287882ceb1f7db09609b48bc6f96efe89bbf8376f5b19cd13f1f720c6de52b5e0405efa0e68301a8a936f42337233ac4bba21a80500cc0654017ea8d3	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd8c4c44090fe6df3be82bacf27e7ce6fa9240d3126e96a9ed9a0a50e3a25c001d6637bdefa427548bf1bf154e7048fc47ededafa0e909588017da70fe2caf420	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc2fe101cb47ef2b356177379e06cf1f0be8d4d8cfe59a57830a8fdfa7331ea50ee429a6d3c5fa005169a0700d4f793bcfdeedb3533e41f65decd8914cae66589	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5ec53e83801df0d0c2fee937186a203d2956f5ffc9703e3bf51688e5d367260c222db4eb7a4895598bee242e7596416efe6bcadb21cca634a42290bb3c2162d1	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8a97f9f906cdc292d426bb0f3ebd1c040681b8d65919ab181f61bb2a8c6c4860d36661b84f60f2ed59fe2f7eb7b377c8d1f10f7373702a04531974a91e5a44b9	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x07cab64f765b1c9b6073d52ab136973c974969df0b58e9ca59fa24285edeceff78f6aa33deda4374687dc4590488ef857eb7817c57e09423823e1b85d8492cfe	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb8cfa7881b9e546ddac82b011f3600dc82d347fdf83c7b46d0f84aaa8cbdec1e733eb1bfab507210d08475863104cf6be92c73b89c9661394f1f0d803dd2bf84	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c8c0da637ab47f621bacbafd0519561c569e206fab632887dd057eb9e40f47716931e7c41c69136b737f97a90a9d0dec4fd804cd76fa65d50ad7a3061f94587	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x41a6853f2810f64f6c6f44b17ca2b8c22ce668b43eae6141123a5c7ead30480709222d54e5b9f0d03e4b1384ab76a744c24afbd94b22d55bc64fe5ce0291c65d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x39683a3aba907622d7c5b1b980206534db406cf4d047ac11ea4513b3fb4b332f010d683ad37bfb303fe35fdef9247c81de72a1420441576a5a64e677a14fdb26	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xea4d94b52731130641c785ca79164a4a605597360856819b8a9c59b2d365331a537cbfa28e9ea639421bb93228cfd7caae30322addeeadbd583d98740f332b26	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c3d0f42703780d428d3cde3ed7f459bb4a306fce9c65a15ad72b1ac03858e13d2864b8f3124ffa9b6662451bed7817b59450a681cfcc2a76c877b7f4576a208	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4c5f695a23612b1bc93a3f57f997d08599b39c5a060d8c99c5fd256c54fff6a14c8344c132fe260eb32348d025bfdc9cb4dfa7bd08a6d1cdb24b16ee6c467824	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb566ba866076f93f65fa8620f265020a1aa365050926f30312c9af96b357059065ae6a324703ea698f646f71738bc8f1266cff2500bc7e82a2a4dfe0482bb812	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4c9abd669f6f9b9713429349997926436257dfa2265abe1ae5d78cb45e19bfe02681d865a85a8388dc33ec0dccd05b19b9291a63b09549c450f5a21196febf52	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb29aad52cb0aaea8974b7feab3f927fa1a79689f265f5d17e36cf0da5464336dbb020865446928acecd8dd178fe4ef964804224fae64912fa12107d5e8a30b7b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe0eb7b23c63b6587b35c2421da2159573e5025acc84a0acd3027a0b8818ebec17226d84710c31972cf84a6f1f95dbf39baf7c5fcade3c7c559938f4d25e45d56	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x77d80890a3fe28898f33c071a5fb02a35fc8bc4a76a11145196bc37648f3a6dc1bf969ce33086b992d265252fe51c6a7ca1fc1c8eec6ff921b63da794ec47812	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf7eb5d02d1df34c408c59d2cd9c0c399bd363306112a91afdab66bd46b2efcbce1690ecc4da1ad33838c1e211d1bf2cac1b40e78fb780b60f37e512feeed8cc2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x289787cdcf1e950abf15ac2337a73fdf8ab94517e1956a431293978e23e48b79233556a9c1d96c9c6d73da6453d4694b150ac38e6516b0ff74b8bcde7dc83aec	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4396ce25d869692acefae7c9339fe03d7340bf8c980323615de68253c5dc794eca0a898506b9d230cda7d099677104803933e55f7fcf4cf84759fe01786ae8c0	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x85bab07a6724a7d7ed6cc07294d89b3e9c8a2bcd6b61802c63f1a825eacb1c9055c2cdf7937a50c75bdebc9cb41c54b6b05049bdeb66bb09f2f2ba9529a98688	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf5a937ebc744693dd30f66d134fe84d76f93617d2a95ad51ae504c09e7546a9b6479a558f80938d6bc6e7c7292c4b6ca45d40a04f8df5c15c641e13f14ad67ec	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x78ea81db6b2194180d5daf6df61edd9476aba1c51caa91216bc302ea8a0607aa9f0bfc2621a767afde055c5d350579787aad186f73d2326c32c748ed5cde570a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe3326eca8a3795b21678cd40b411b27c1dcce1d538a33f1371beafca2246de115ff7974772cb35a79776c83b023a4bed1ae287867206bbce63ac1d01a2fb7d81	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x38d746dfb9bfe3090c0d5fa3c80a412dc394b12c19ca2af2d80c62a55ce9b4baec9a5bd9c1b0b0086da40dc7f35b6eb7dad4d015541723249c434c356c574b25	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbf6f4f337c57d2ecb5e9421948459971ae97d207f246ba679b059b9c2328072f51d05edc90bc6ebcea6e92a3b4aefa2c69e2fb72d8014cf1e408bfa8ec2a0248	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc38c71c630c28bb21a9732fb5a16fea3f6e95631fa02d0ae2bd9abddf865039513a9cc8f65068e2d3824c85182b2309d3c86da55334a55bb2fac6acd20f54d7c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x531a20a3f252b6bc8f66708d0a31445be970ae0366e93e8bf9b14b0ca9c4eb8a56f3a6a46b8e7b967fc49ceff482157e3d6c8e06908f166a022f2d311be6c858	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe8d2615f9934015f8a684163194ce53af4b288048a1c346742eb8ad460f0f5bf3be1033338f5faa6bd0b40d2fe4311e5f1d41f2090d338ae286e6bac8d3b5eb2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x836aa7800d12ec4280ce3f51093251dc49b8bc77184ab11ceceeda5e14c15dc149ae7db47787f80941663e57984fb194c61e34a56617a684bc8ee6ec8491572a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x37444e1dbbe995ec2c5c1b70ce07c1130508cb97cbd43f6bde0a3a5e9d06c3adfaa3fc34c745195556c9ed071f2ef5ba7d539748ad4db4e214c1b957c9cba1f4	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x168068138a7073d73fe6dee015c17be9f8cf444b0701f43dfcd85807c3ee3e065edf83bf9664deb3d9b5f99cfbf3e4a5dd744b37b58626b42a73dff3c99cff41	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x56df6e3e28606527ef6d14a9451a0256c214db0ccb6b4160dca6ece5779abac06d7587ec0da46d17d9d464fff16f0941ad181ae0652ca8513b7344ab91189d44	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe40eadfd01a5f5f8ebb53476f7a9d5888ffba1decae04ecc7baff2ce8b7a39581d851838c08f712a13a8eb3bcc3ff192f02aa45abe2d2b72af8ef69903f3547f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x54cd9918f87a8710f65dc81daa19e92763ebe942e011353501a581348c6a70e58b74748545f37cb2aedcc6b2281897b06a66141b15b94d5e0e17912dcd0bbf97	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x24eca5629626491f4ce67e5393a231e8cb340113bdd92e8c881597e2a09ea8f265feb2a77485103b93fd0fea9fc89c9e6d27cd87fbb7b5dfb3f36d735f244e55	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2e35e9f085fcbca5dab777d193816d6c72fc2eace4a03eb48274a0936d8676c4b2b4464b5330a6f887d9d031c8aafd024afa08c0554803ea43974b376dfc81b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xca8cfee5d6901be3376754a6b73ae49414a88128903ab6bec081456095eed2aff904d5934bfb947ec13f9b5c95ccd4087b732ba2af43d4947b9a8e15f7c41b08	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5d6e2036de11fa1174766f3cabdff461f1c620d395c61c8d1ca2284a9ec80275d8439f2064284c04dadaf579559a81c05b986d1ad06f297f65f5819f4780b04	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ca94cb5bd6736059a0c6418520cd5b1eefcc8da3e9965e06cc9208fcf9a77dca1aba5c683eb9a01e56deff686f9a715c6f25f1ef568e3aa2b129e583229d82c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x83ff1f8ac2514487c66f730062f45230e782608100404f55808ef7d7161a93cf1ab9e138873057d7b66128dac1439acc46837ee4cea306db85bff12f5a170036	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa052a47c67cb2a0af0d4cd9cd82754c5fdd427efb6100b9a30fac5637b70f7204c428f015d8c328afdab5d6f5f0873931c39f36d450b9b99bef1efea450aa12	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d7fa8ec51edeb767a7eeec2db11e0009e7ea88410853cd3dbdba9e82d711fc053d9dbbe5b5be80f0fbe5d93c4ef177c54fa7ca528e0c5fac5317eb5002e2872	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6984ec118384002a7a83e3f2e62c78b20f1711fc1e31cacf5b9d04d3d7dd54a1ad8f73663e70196e19541dc6c6af8360e1cd4baa8d929ee6a2fe75d1c75ca727	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x51ca12883b33d2b1b768fbe6527bcd77c3176acaca332a30f8f128b6a485bbc906dfbdc60303b36c891b56aa12b269e69412b652513611a028063ca20254ef1e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x90cf745eae203ba6cc32cc478de399b554f79be023160bf7fa0ef48c84ef37368d92982a1e887874446c49ef17ca8ddd577bf046006578b9f5e201cc345deb57	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe1ceeb63d3334db5706ea89f28588e5d6275cb472b8cca933f9bf1463829f8f7bf495ceb1c0b35eb8efa2622c01ddc9957245135cff370896fe1c5ecee0e7ad7	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d5e88c864e41222cc1a12a80406925a3b5a8d1c0342904b86ced1ffd4433e5ef016fa70e0f5953a31c20724330da61f8d08de3f49f594ce7b52df6454b8f331	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xce63e69c6f95e56f932f219f191c1f593ca9a8abb9cc4df94275e8041abe9ce2ea2a1375424b9e05edc820a8165749cf27a4a9955b209f8af245bdd49cf716f2	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8cae3cef3c1b82e1b0f4f13ba675243c4a4ff105c4b231ca983b016a760ca523e1d6ef50a4c98baf901f71d3c6dd6150af2e5357c7ee817ca66e795f8d033db	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb39c55f8f2443896f529db75a4f48c7f7f675971e303785e26ae3ba0dc08e0d6d3debec8a1f0eb53c45f8c8ad5cb1f936b320a9822678305b4b6a7d5bfd4d49	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb19e620be24e563c5ff4a6d9dc48d5c3789cc4cb76b1b29c5d4c5508577e13622d45d2378f08e93cbd3725d3a0d25a4cdfff3896599b0317a631aa2642aabd0	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd68f06979ae63a581270b1d42e7a82ababd60ba07e8a23b2b12fbd5218b3e7d85106f0d3553976df783e2709bbd2a60eae422ac03f68035d8b870269aaa78c6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf826a705c0cfeed6f580f40064563f0089b03ad967e935ab394cd9caf3325fb7a3cbed2e675c9d92a870e0df9c4cde37aa00755932e23fae21d02f550201cc5a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x92467c10de888dc9304f6ba81613d623e38b8d8cdd5c28511bfabc5b6bcbd06a6ca36e0f3c976a2fac1f8cd7049b004ec95f281f5aebd4e6a01fffbe55f9c40e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcf606e91239744a7559f532f317249988628ffd78d0ff568e63a86d161e228733261fb1701c5cea247f7a5e9f842414e3059b9b476d08d734f5f22588ea193c6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7bb4b5fffc30d56fc7d79ee3f5f2a9e191910cff1ed31cec67a8095b116674d80a4e86bc8153c31a12b8efa101784c1cffaa182f7a94ad5842f1423af320d3a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf0467f8fa7fd1628affd340e463bb0fb92b8a1606e36a6feec3dba971c55637969e4966a74942cdd642432d3bf9f0bf2cb5f01de1fe52eaf00fa1a2b74250782	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0dc2c69cb93574eba3c41d2104246ccaec233684b7a0b8c1ea4b099c52de81a8540bbaa42bc13406f14b30a4926b589926b00583c71df01aa0a9f1af68bffea	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c71e45f261f5a90753d0374d5ca4cd3082fe263afbd538306d86e7f481b3b391fc722da8596d000926d4863138b97423f1d6197dcd4aa508a54e2d5fe34a24e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5186faf83fa27e6b8d5954e317e9f371b4d9e4d67345940a30e567a89fe26c165795fb3d2ea9f51c75c76d2c67f1b8ce7a7d189382735eb4e55e9c5bee5731a8	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf73500d2a63f013b29af6b1286edfbef1748c14b4e6171f648a0a7d6026e93ffc582341df938361121f5376fa2dfd41fbbb148006d7c0418fd2c0828ae944f9a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f85b57eaf2ba1dc102809a28943a30a8141066988d1a03b259fb743813c10c70447173e11c10ba4ebc8ba1520f0f96d63926a68e80c30409e247358b49d289f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x229035526e50640bbe18ad97787ec3af212aeb49537faee51b289e289191e1d4fb784871109ba8970fff1a009437ac1be36f9aa7d5399c40fe23b78806e4743e	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x00e95146e5a4c0da4e3c1092acd893cf263219f59526e1b0669c60995ae4617a3de5ddcc13ed9b045f3836f4cedf5d327d81380df6abd543fb471f504712bd15	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8f222dd5e9c253a098a97842d1807e0d79bc04f5cab3e2b2bc741a303c86744aba8c4a0bff174b8d968cfb34e13146d4c790379836071d93a6fb40775e1a148	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x503560c3904b9b31aacddaa6b24e28bb281a59379e0418b61c5830c229f32b0cd09bdbc9439658e9e73f3915d9b942b786ce8428ac8ac37562e275340fdc00f6	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe39ae110abab976bc49071b955865beef61ff5386b44084da8caed4bffc5003596f9aac5210becbff887b99d0059a66cd416c455ff9584bd2ccd60ab9d2e16c9	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1576355537000000	1638822737000000	1670358737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2319c6df84541deb9f338975a88961ee2d249dd232a5b436094458252a12620ec1fa37079e6cd6b2c6df9799b96c049c761fa52ce407257cede25192b46bb681	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576355237000000	1576960037000000	1639427237000000	1670963237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xced7569d8caf6d437c90e6a49c0c5dc964f164774c279cc09998c60fb7436d5546973212590120992a09af2613498c02d268a398323441563ca9f3c78808c0fd	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1576959737000000	1577564537000000	1640031737000000	1671567737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xac25341f73d635190247ffbfaa8fd132b2f24c2577cd4b3b4ae0be5696b15948b5247bf1151a1e841b06e25e8260888d493cda748314ab48235bbcbb6fb6199d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xae74652701ec321f11f162d2b67709b0fd948d82ef8400e724005f16cc297d7f9271d4af31067b04b3f54f206171f7801f39d30e0c9dedda6ceb8a3425b5c1e5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x864bacc543ebd1a19fad130ba678f6626e1ad383a554f4766b17f6990827e0c610bc0ac71a78bbfac7fe8153de5ccf3cc19283f8fcb74e34cd57fe8ebfa5ec82	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1578773237000000	1579378037000000	1641845237000000	1673381237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x772f566cf43fe36425f5f89653aabcf4147610083038c05504d63fc61ac4ba67bf51db775678d05d6c85b69b5be7604603fb47bfc2adca58e033327b44a2282b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579377737000000	1579982537000000	1642449737000000	1673985737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x564bedd2f871636f9819f1701a1ef7f9ac78e9f78e2ba8f20ef05d45e16f85ef5b46320ac72d61be72df733b27732fffcd2ab70065297baffa404bcf3d4e9e6b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1579982237000000	1580587037000000	1643054237000000	1674590237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd4c3879e9db6a3438cbc98e5b50a4358e6763470adf4a96b4b11486d6eec57cfc33e620df5916788bbc64204b4df6ea4840f777e1020a81dd67760968c67f324	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1580586737000000	1581191537000000	1643658737000000	1675194737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x70c9c02f3527ef6694c79d82534da04600ab4f00006e25b70cca3b1ce5b5cb52eb7118d698538aadb6042cb426c413b539e475bff7531dc52ba749f544c096ae	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581191237000000	1581796037000000	1644263237000000	1675799237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7e85a3ecf7597e87f030b4773bf317c00722bb7c3579412d260d21f03fb495ebd7087b9708e6cc921bae0cfec9d8a1af02098760cde5927199634687d6f4ea6a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1581795737000000	1582400537000000	1644867737000000	1676403737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbfa7eccf91714014bcbe319e5108a27578dadae70c059837266e980e83babc9c503ed4887dc33c065942df38eb3f6416c8bfb3c37d762425285068aca372807c	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1582400237000000	1583005037000000	1645472237000000	1677008237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x78f7700792a942f5b7a3c0f08f36caf57e7bf6e5a39228ba8160269d8abb8e5f3ee8e70713faefc1c782ad717987069508e42e29c238b6e9e56d064fcc00e812	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583004737000000	1583609537000000	1646076737000000	1677612737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9da795bb6c20aeca21346db199b04a5763e8dcbb3c5c86ee397662b43257b6948464cfa52a1f772b0aa71f026620f437a3cfc0a6b8ce81c2a9ecf41c43b2d020	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1583609237000000	1584214037000000	1646681237000000	1678217237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb6c1f676df4d2d9ae2d5338b2dc97910f181b345f30208fbb8a8fc8b6c8982b35df9ef6dd69778886f5c7303c1a2dbaf9701ef9a239a5d9f2c8522801f47b0bf	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584213737000000	1584818537000000	1647285737000000	1678821737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xad63200a1a01116e2c504545098ff4f4ae25adb396af89ac7887fc9dea4375a887e20dc6bdf3b2ea1e71e0b8f56b3a0f6c1645dd5da143a7ef5945c8796f3b3f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1584818237000000	1585423037000000	1647890237000000	1679426237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5bb223bd6cd75d0c5222c15699061736aec77b4f8ea290033d9e4dffd379cef5b2d150086d1d755a46e4e9e760ea627fa14b43078559aab46410b2a094193397	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1585422737000000	1586027537000000	1648494737000000	1680030737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1e759cfc398b1f4295df22e6d2e0fe31d1c7d13d10732b01230ecd1d2824049aef67c5615f910aa34d6b1e09096d223929598eba112be3d1262bd936f3dbe2dd	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586027237000000	1586632037000000	1649099237000000	1680635237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcdb011c6bb1f377be7a1f2a7ae3e70a12de0338cb9cb5939eb3584158b8e033f7c9b1c0cb3cef2ea6f783c83bd5f244db4d6cf6f485fe4180125a62ecf421606	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1586631737000000	1587236537000000	1649703737000000	1681239737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe64ec3e5ad56f00ba0ab63a95ac9377d36e5d0d80fb9cd8ebbb18c15ec3bc90f86becc717ce276f160b3c9c7b9d59569faaf5b224de18399d83c869cb4e995c5	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587236237000000	1587841037000000	1650308237000000	1681844237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7aab0440274f4a510d4f017c361e93b8af4bbc75a927640eec06c6eb32b435afa17d108d7b68aeef64e3e58b5be45e4b9c7245a8a6fe09fdbbe6a530bbeb931f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1587840737000000	1588445537000000	1650912737000000	1682448737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x29caefaece64b5fcfde10188aee92aa318f6acd26025254127fafa119f0f7167d63b1ed92e9a62f17b9fcfc93172304faa55b13e7687aec91ae33c7c5e1f07ce	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1588445237000000	1589050037000000	1651517237000000	1683053237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6bcb18e2a54d7e5da88b5c295302282f74f9d7dbec99ec9179a498323c4d014eec167986ef5832def1452c8eccd79dd88279c8c843cfbc33069fd3908129f3ec	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589049737000000	1589654537000000	1652121737000000	1683657737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4e0be986ca977c7b56ac461efcfce864b4e3a2de787c292833ece2a87869fce62c19ebd9ccaf8cb5898b45ccad2c46a1f7ec3b87e4048624180815f48e91e23b	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1589654237000000	1590259037000000	1652726237000000	1684262237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe75f7f1f2cf3c7dcabe140dea660bdeff98d0d17b1effe76a76fea3fc753e56536918bdf3be5d894519cb68e2c0f9459f89bc46daee47d0d9e7bc1cb5c7f9709	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590258737000000	1590863537000000	1653330737000000	1684866737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcbb44601067819166da5e2a446a868d397c92768b2f43eecd645d1042cbb631ac3df7e998853338f5c48e6c80d083762a8770906dc6f15a956715930ab0ac64d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1590863237000000	1591468037000000	1653935237000000	1685471237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d2954d87129bcc541baa70ec0c5cc3d1a34c567954bcf52654c510a2169f6a72dc55c6da2569233a2ee5758c38c35fe23a3c1f69c77299873a468900b67ca7f	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1591467737000000	1592072537000000	1654539737000000	1686075737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xea42839161e7fe2c6357f2f54663d81d566af9fe01c2080ae91351e10f60d28a909158e6ba83013e39c8eb356de63da478383d146710e5acf8b7afb4585c8471	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592072237000000	1592677037000000	1655144237000000	1686680237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8f0699a0ee7dfb3d5be0621f43dc530c2010a6f10d1f96ad6855f4224e95b868dd98d38d32d69e9effe750b11f9053cb984a11700ba2308112fd1745ae0035eb	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1592676737000000	1593281537000000	1655748737000000	1687284737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x516d529682947b8b39c87b220e8db72aeefc236c2fc14bbc9528c1641460b38fc384d0dbda367942a9c9ea0a73f016e66c3c449786763520d0801c8ce046b15d	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593281237000000	1593886037000000	1656353237000000	1687889237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9e5b77c99e356b386c20393d646d1cc11784d73d62354fb3b09ff9b20664dff6c2a1d77995cd5dbd7217d826dfa416142323df46529d73f7bd3904988abae283	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1593885737000000	1594490537000000	1656957737000000	1688493737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6308a16fef23e3e3e51c8651a3fe256ba4c2e0d69ca8073516d1233794ad1454157c19c6e7ba9b94ca81d259e60a49371ea0fd2a3197b259597704b42ae4d809	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1594490237000000	1595095037000000	1657562237000000	1689098237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc76a370b8877de9e7dd614e0ba6edff39a975cfb17e8de0bc986053544f0ee9dd004632412b8e6237f1a027bf9a1136f1fe5e8f0cf04b99c444972e149cf0b6a	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1595094737000000	1595699537000000	1658166737000000	1689702737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1575750737000000	1578169937000000	1638822737000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\xe0a056193b5c31a9c643e8a67a13c48117ff4f5d6260dfdd808c221180b335d95ef64f53e1cc9a89f9edda000ab2ce8ca0a7c2aeaf01adeb022d186fa4dc1700
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	http://localhost:8081/
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
1	pbkdf2_sha256$150000$1scSHxZz6Nne$p4bu7H1Wc0dHWoN+3pQXBCNE2oBxEp6HXyw/vJaZ4pM=	\N	f	Bank				f	t	2019-12-07 21:32:27.834366+01
2	pbkdf2_sha256$150000$IecUQpDK0QFA$qjsdr5sgiv6HEAjBTUEerHr++vHjjTBdqfrmJBpP2Xk=	\N	f	Exchange				f	t	2019-12-07 21:32:27.89477+01
3	pbkdf2_sha256$150000$KkQn8XYf2Iv3$EPEWiAhk3RfGWxMFnG4ug5PYa3t9QSm2Dp+uKaA9zlk=	\N	f	Tor				f	t	2019-12-07 21:32:27.950021+01
4	pbkdf2_sha256$150000$gvPQUzv6dEfp$/3Zxr0Ziny0qp2V90pUVOL/HWpcwNmGwk72JU0mJxJg=	\N	f	GNUnet				f	t	2019-12-07 21:32:28.004845+01
5	pbkdf2_sha256$150000$hggaTX9SWtXB$gfSo/gA0/ngd7zBO5IxUuoAmps5T8tdaQH9XoFGTUMY=	\N	f	Taler				f	t	2019-12-07 21:32:28.06112+01
6	pbkdf2_sha256$150000$T8hvQtveMk1b$/fRiN8um3PiQIW3YRvBneH1T8FHhjS1BSdrwjqfO/2s=	\N	f	FSF				f	t	2019-12-07 21:32:28.117656+01
7	pbkdf2_sha256$150000$GgH4zo1tnBrK$TlqmgxhXTreY+bExTe5PB5qaaLCXnYn8e8ojOGr3DX4=	\N	f	Tutorial				f	t	2019-12-07 21:32:28.174294+01
8	pbkdf2_sha256$150000$RLP49RVXbLY3$mDO7y35k46nw2OGR6dnuYUmg6ZXI8AK10RGN1SOyzbY=	\N	f	Survey				f	t	2019-12-07 21:32:28.230649+01
9	pbkdf2_sha256$150000$Kve2AeaFnQjV$a7laFg/gAnYQ6Dh1KgK24qxztkxkHXMIVmBmIKkV3b4=	\N	f	testuser-OUGSayzp				f	t	2019-12-07 21:32:29.953967+01
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
\\x622a35ab53d1e74953e65242e9af57d6b5e2c4ac8e9248c346396b6fb7088554ab109336027b01ba1fae50f96318f0fdb36690cc0698b6b9b05037d14eb06c82	\\x00800003a6e841bbedd099e2c28a5897dc1f4957974773ad98811e036c8f312e613221a098f5794e1c581a0435a84048f89fc91860bce77d8a506f6fca82597b63cc7fc48626463eb3d0b06b0d484e9a97f4ccfd12624e4e5510101324160f5991874f83c2e4e119f12b46b0ed8ba79234591f21b33f2de0fdf89a0a5f99c91a13ba9ed1010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x5d7155e5a7869a3dbc228728f1f397f8c94bbe20341ebe6d9a1477f1454a07f71dfd796b45237a04d2ea0587645eac068e291e69d2a9db346baa2d73ed465204	1576355237000000	1576960037000000	1639427237000000	1670963237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32f96de50950156d7a05ee31101dc082a6d401b2ea93e05b5ae83205531bed49962a41d443f57cc35262b9eded861261084ca6d71c82a1b72e76759ba8e9c08e	\\x00800003a5739b1fbef8f2c06745226aea979401b679028a18f29d74fa9894e24fa51327aaad54bb67620ed5ac28af7a8fb2ffa9cc6bbe5c1758969b0b87a1f975f6a1c690b2f135069d1dc230bafbbf7817f3b615c20d5f3cd714f6c04b4c7b6803ad3bfd4cbe7325bfe7072ad65c6fb1171285f11e1b489040c76e7eb5a840fd9c8aed010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xbc63ec8726da7d8354f076d4f94cecd6e7cc1cbef97c6ca60a54d10c2192f8cdfad0ebab40d174c9a78f2769e0b662b47400304d889e8e335254d4f5552ab102	1577564237000000	1578169037000000	1640636237000000	1672172237000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf21514d121046e9bc7f992c25f16475c5955222aba3063a134226f5526980e26e271e77c6001102e360cb4beba80b322426cce152cb57371444f368e92fda4a5	\\x00800003d5117f04f1b7a81274cf0df7b633f1aaf0948379ca8bff8bb09b052005f189bb65bcec89bcca481aaa560b7b934de2a0065633d87f7d40dadab0d675940cc42c1693f5f35fe8086f755cc202c8473e77a12387f24f3aef6086a6d758c530f843bc7875e09bb3e59f37f24a7aefe1d7e19de11d9e48f36886fe3989b88af6db3b010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x1cedbb53a0ac15ae41bb914e66863f0bd3753d6309978134f5cc6dcb7e2691f34be2d20ded1138a582512f8acf2b8f8d318a957721b134d66bcbf5de6a5b1c0e	1575750737000000	1576355537000000	1638822737000000	1670358737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f0e72c7b9d1ba304cdf0722e2881e9365c05250bb20a9d78f9a9e3c5ed14f23dca8233714cdb16f56557d18ad4ee2272b594ba654e27176e51a43cca2919ed3	\\x00800003c193c3f6bea99da763de20dd9261a71cda1d2bc91f929c86a8b35e2220f01567946c43089b8d73b6bc736eb8d4e2afa235cf7b673291d12313426ee0e603e6e2973004da88f20a12ab47f0f00ac1abe1b1db167c6a109c777746e25616972b7dffa74f3382b883eb206dfd9e688e3ed666b565f0f3ba6dddbecd036a0369c92b010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x7de728b2ed6550131483a66e8b76ea5c9ded3542f9de1432c1c94aa6c153cacdeaa580978b90269c283a690c636931e36f30167cb9e64f11e13d08f17af22709	1576959737000000	1577564537000000	1640031737000000	1671567737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b00c23bb5f7cdf4a3d40ff98e6f3998c86becb722636c10664abf4a885e9e5a30cf3986b01547a98982d2f07106a18eb65f9a77926c76b7b1e25eaa7f8b8fc4	\\x00800003dd385911f8d24ddce551cbf429794b17f02ca5476c993cf3b20a708ce07f1692e4e7e36cfe9a13db3a42157b4ef2ceb0d1e6b1e49bc2f4d61a00c17e061b8deb66ac287f647fc1eee320cd03fc6d42b57f0053dea72c9fece170ba9f0ef600575137baafe3f628ce5752240f7ca702c7adba6c86ed333142df4b249dda2c25e9010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x4389c8cbb57920ed672656a12d85219d3494f650cd021ed4daf69d91dc23b4c1d99faac274fc0b8098e20a570a90708fd2834ef28b0235d8329a1c2421bd5e06	1578168737000000	1578773537000000	1641240737000000	1672776737000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabf82ed13d60d4552c8708e8412966da80d9bc5413e63d148fe9366ac263a6913d3424e2afbf95e22c3f181ff6b526135c6d5b0caec28df9fd1a4629281094c8	\\x00800003a87068e5b14e05a93f5ff0bbf696fb35e6ba4fc94cc18f8e49826a1de5279e347f9be6bf6a9eae179911e1f8c2843df4502b42a7f5689e9787037b3b14ee9da24cf62cfdf361a28ddae33163a6c72af657223992d5eb5318056df27784549ef17504e291d8da39a8387037354853da3324da7f7f72e7ef1ec8dc42c95047c381010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x645cfce9e3c6035cba6e1ba26fad1f00c59c39ca8cf222da184498966db7e2e702ed5da223188f4122ff6c06b372e21b70c1bba9fece45dee80882b471d41606	1576355237000000	1576960037000000	1639427237000000	1670963237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f9cfc61778c6a0074fbc1b773efb0838aa0419097b1bf3882a22aeda776bcae93d59cb7180656b2a66875bb5cd73d82500e4b305d8300df70f314861bb1ced9	\\x00800003b6081771c55a2841ebd5ac21e0e53b95ea5af51bf74f4f5f540bc42b33984fdee0644213de8e2f994be3af411aca91e9278a601c44cc005489c021d97db9aefdd5ee27fb65867469876bd5554fa26bb80cda824381be61bed521b2f9906d9d4fc458bf8dd18d4a7fcd138a0061ec5cb6e255a3ab196912270848467a827c4aa9010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x0cdcc4b5deec31d62d41ed5ef9c0fab12c15052a6793dd55c8909769e217916f4eb1e9d18cba9752cbe3e148ae4a51ffdf789d8ddc610a59c8687806a14cec09	1577564237000000	1578169037000000	1640636237000000	1672172237000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a1b41095625c25cd32fa24f466e5bbb96b9eaa367de5feb0aeb320e18c72c58ea717abb8e667a95f8f9d96d8dccbddebb8dcd2dd77bc56614bd081dee4097a4	\\x00800003e30d1b272d6bb3cb2dc289997831eb662a678d5daac01970dc004beff061e6191af36cd33132206358dc5564a30cfa5b8bba756b3bb1a752c842a15cb5834f78c0d565d3bb0ea7ed62d13a3c6785ef620cf83f0b29232a7550a32d23fcd9262e22e3d5f36c4c32c9829977ed7dc35bce2bf2e9c05b79f27c494b4c6db3bc2e1d010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x24e93bae324deb068f55fec7e73ecfcc585003cf259f3cfb18935bfb59b4a1bc7d1fc9e5106275b878030c6863d6adcb02d8567030480fa330985fa05824cc0a	1575750737000000	1576355537000000	1638822737000000	1670358737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a96d53031727122fe9f46226d368629459282aec3682bfc7cc69bb8a8d6f09d23fbfd120cec1506f0fb79de08dc783c4e755dee906683b7f1960b4d0d9160df	\\x00800003afb88dde3569d7a60d6dd511b087516ce3aa47835930a82d61a2c48aafd1e4cce0c06f2aa242500a72ccc373d1ae05e70fe30cab57cd33c1b8ae47df54723f8d29b827cc6fc7f4c78e73e0fd357a997870e8bd27ad025d39cef75a6b37de4f3054e23fb9cf5b816a07f2b146cbf5f6f21631b0e6f73958f495ecc0b92f96d219010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x540bac6171dbaf04603866847dae58d861f3914a2cc30035ecb50836103c7934ce2b2d87f0f9d913c4fb35391c04a88a393daf18b459f40f6b18c1cc9d6f210b	1576959737000000	1577564537000000	1640031737000000	1671567737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe644fa873cb9111009969ece07d7eec691348806f68ff8c9e712c3b5b3c2c70b9c6720e97801e036561133c210c19c352e888cb4d942c161e107eff944ded346	\\x00800003c0641c18bbdc78ada62904d9e061190eef6357e6b3119df387028898b213c6cf79cf6cfdf701b7371704031a429f594ffd92bae1a3417451dd6789cba0f2aa195e0c2c6fba86378e196dded8f59f43675eaf868c8c14cb0cca3fa1304d238f0784a4dad7ff758931d613bca7ff3c8278683eb939453abe03dc19760640aecb49010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x722745ded1de7f112790af6a9513537f77c98288a67412d49754d973b91e779a6159f4bbbedc82290ec889a14f7590d1ee8659c93629ef4d31237d79001ae104	1578168737000000	1578773537000000	1641240737000000	1672776737000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22841df4c01d3e745e26bab5e05a90de308767a4d728d748954beeb93aaa8e70af96624d4b507c79ee194f519816b30b40b4d363541d34e44f09024e4a99240f	\\x00800003dd43824d29df2bf1c193e79cff5124deb9aa75362072f7878cf9529e5f5f7baf744d8f4c1a7f1d5fefd96bca1d515f827248914dbfd12b2e90ce9156f26471be7d5938ad4a94b327ae9117b806660ee7063f26a2ecd5af326e57d0a1b400390be87d84f5074c6a6ef175e60525627162b3d0a059beafd791db950fd73d817e4f010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xef6594c7ab9559a294f6b446947cc3eccb765041cf07d055c65bfe08fd0b49a943e163afeeaf194fd494706a0ce4fe804b46c7fb7d81f2772f36683a5432950b	1576355237000000	1576960037000000	1639427237000000	1670963237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x54cca7796bae348d1ec216927b94db482b5aab18b09eb433c8047a088c75727139591c54ca1d1c273f72840241f7ab543ce230dc748d671250fe0121bea93996	\\x00800003c7078fc694cdf90a91f1ace9e0626c8ea4f54df95345326d9d7c85ec03a7269d99f0707ea28b069940ff53f99d59a8a5fa509dd448f4ec06d2b3eee9a24ebe379a21672f81381f3545b2bfc3e413ad85040e2d09021a920feae288601dd0c500bb1537059c0f44c76eda011aaad0453a717b66d3091774dbb32ec8067d6c2b9f010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x87651a2f55a33ed753d0929f70b948384f1ac5dad61592406440c164b2409a32e54e7fd82a7b463095c2431c5bd538c6c25fde547ac4944a7c99bf05aba9e40f	1577564237000000	1578169037000000	1640636237000000	1672172237000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa06ade8eac05664ae4b3d8ac5775b4efbbb4520cccdbb5b75d172e26d718603095ab2c33f046953127e23a3d1f1b071db864871b5ff3f89c27ed16aef96ea2f3	\\x00800003a450f80dc9333c1acff3059ffe19aed77aeb304808da96898622418958431d30d98ef98fa567715f9bd3ff954eb8de2741a3d7ba79c2e57425df039aee164a5499889ee1a342ba461d6cf51a95b38388bdb73393bfb3eb8b66ec8ddb62b67ab0f0f0159c449ad1cada0a5ad98ed4ef56f03c434cf16dafe3abd889752ff56813010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x8a2c05baf33203e70ce26635d47400ef84fd9b0ec8653b4ab4377adc31718f1b98928bc3d22de8d83774245ff5a243f7e969d7a28e07d4a4cc161e8f1c7c9601	1575750737000000	1576355537000000	1638822737000000	1670358737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfe29f81e7464847c61465108f2ba328d41709d6dab5df9d49d9cc5927ea121cb5b3fda7139ee521cfc919b8347b1fdcb0043dffb2dc45d9b91c5ce903ccdafe8	\\x00800003d04609a0ed378f22c0473e84a5be21d1191b0a07d895c8a04fc4132599a05ed770f1e063904d40e2a3b078042e2d900e61b52295a4af56fb912e4b5c90523d754cf475021fc379f31e0811f2259db27e21f57e71da8b3edcbd0591f4aa7c5568face344801d7c8e1a5fbdea5f1707e5bc516ee248b07fd75fbbb76f99ecf6411010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xc04b2bcb0fb1633545599a5d4e7a816e15ea319d571f1c1fdccee303349975990c6a0d81c64f94294adb07e6ad0e4c11a1dc61e2bbc906bf73a779fae8e5c306	1576959737000000	1577564537000000	1640031737000000	1671567737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe51d2b754308e414e37e17cfd48c9e8b424cef77803e45524b156cfda21d95f3143fe36e47d7184951839223b5d557b15631cb7d56aa4a14ef6ac226c570a159	\\x00800003bebfe5c6de1668e772743af60b38bb453bdde820e5de14babfd3aa3ae6963014371cfe5705d6bc1fe6ef705b780c59f563a7476911f646dfbfeee3fc8f4e49630367b27ede88b769a056d12b7bf7bf3330ea4b59f3893e1a91734aeff4490f60ca343101d6f5f088b540063a3bd075d9f5c0c5905cae5bae42595b00a9911fdb010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x1904ac255d69aaf289d4a71f84941d3f2350968cbe13594c72f4871e373fc439574bd30d29dd9a228a1c107fd6a0eeb9b5121d52f935cf86489b104adfd7ab07	1578168737000000	1578773537000000	1641240737000000	1672776737000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x51ead506a3af73a755cf32f8409154a7ea014d7f22c9d02731c78d9cf27176b40ad07ac4514b929d8d6ce1dfe2a6826dd761affbbf8daf90cc30761e7c2889e9	\\x00800003cd59e401dfc822c4aaf726f68d5bab3c55f91953e8217d3dca9cecbc7c805636736e7876c5211a19efd9285e4f3264f75eec5e9e59b23f043313e41b245a17df7f53ae98cfb760fba04bd11136ea99b9093239854ec472d7cc82074d33f5c1c0113cf2a4d32c8f2c21b48c369906d73f92e40b21c7493ad53cc392caa3b48ed1010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x5fc8ec2d131f658c62b2935d4c703bd6ee7a75e4114449e3be70c1c5325aa52432410d979d976433362d7bf5f56bd6e4a2fb52fcbc2666b2d2942d379778b101	1576355237000000	1576960037000000	1639427237000000	1670963237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8daf780a3fcf96ae1b215b55f51636baeab09db168ae0aac6c8d9b04426af0d9dcd04e507e117885994811a802cc233ff930f6528e20793e6f8d13fd32a61780	\\x00800003b7be044ec7138a3269abb1d0303a44158312ed2e10a285f2b7c99fcb555ce1ba0fedd9829a5a4500efb1cd7d59ea35201ad9d7602f97aea13635c32d4b0a2ccf8b523579eb82df3c399681e865c516aebfc4b83c3a26e5169aacba000acfb953667bcd0c438646e2d7f9953183a4d38224a2b1b1b24099c5da58f7ae15f28197010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x4fb0ea4aedbad0149cfb64efa647daa8cb3ef2cf6f98a49d1f3a54cbfabae8a91c00427baa97352d54e688fdc8bc761eb97af7fe8e3326b1febbb2d1e45fe504	1577564237000000	1578169037000000	1640636237000000	1672172237000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x53614c144bc850a70f4a20dd2d2787018ab86741838d33a4133f050d6012b9bb41bb6d4ded3f6f5101785ad1397897cc3c395e50702ed28337ce96208fa504f6	\\x00800003e0d3fbe80e362fcbc12c12f5e208ebd4de09469c150af0deb2623d72a7e7f93b3bbf6d50b3853d38a2cbc47505b54f5020c2eba87b541de89e93a6ce2db1968e8557067ba0bdc52a3488e64a60e3b0bb1ec73dfcbcf18f5773c4313f696d30f840a0eaf8ce275e7f39d297304fe19702af597f92f02bd96f666d4033240441fb010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x74f43c0d7262038164621d11629bf3728845087453f5b32b5d2e99345a1e14604517f73020fd1bb7116263fb17bd3d21c77b93b08d670008b439347324ae4103	1575750737000000	1576355537000000	1638822737000000	1670358737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf624ce112bf9343023f18eced827b10eb011c4027234d3edc68a82d77cab2fb9c22d3049a7497b7d649fe941567195f4969ccc15e88bbdba7236cd9477b38b57	\\x00800003c8409efc49f3f42a3e27f026db8aa5a8641ac2b3aca8973ad3ed05c0b21e8f784adf65600ee8830370a0a9dbf9547543781dba8b610e73a53860d7ae4ee70a9b865a8d5eb51e8371b875c6c786d7bb1752248524a00e1591c4f36915eb791d3b2579be82d0dfdcb264928bdc8d66054e7d556d928816351633c22027b7abc211010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xcbe44e396030121fc8a99d8513c6f9c427c14c8b2c6dacf507085d22034136dc789ef363fc5b90e249aa3cdd6e905cce4b5fe4a61a8fdc4111d8be06a3df9d04	1576959737000000	1577564537000000	1640031737000000	1671567737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde111a3bf87b0e4030b5a20b4e90fef2e2c72039296a1ce4e9ec2ed1c0aecbea2144c7c745e983f3a8bb9a17a99463cba86d38ea5ae53cd291bb9fd2a991475f	\\x00800003be5a45a646bd9317c60096ed94ea9a11932b3aae947a54fb1bcbf5e2b2cb224e969ed7895146b7e62d8bc2d5b9aa809658ddd077b8290ead4ae2631a915b5c258e93a9420c80af40d0cc896d46d2c3534be22ee97c080637a0e8a928dee1c2b77820c43db9a90ad9af79d9852f994ab155cd98854bbdb41fc678a8f49458954b010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x230cc218466e23f7ad449a9e43ab877a95914dcb55b58659e1edac1088a927e14f4db8daa98bde9eae6bc98cf94e98354188f9f77fe45e1d7f7888b7e601440b	1578168737000000	1578773537000000	1641240737000000	1672776737000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8a97f9f906cdc292d426bb0f3ebd1c040681b8d65919ab181f61bb2a8c6c4860d36661b84f60f2ed59fe2f7eb7b377c8d1f10f7373702a04531974a91e5a44b9	\\x00800003b3183c0322cce1e318b43868f2f6030e638913db9a4333533cd067112f9244e57911a1c938303b2a73f8bba92f93a7a3b255655e83911c5902ad945f2e334877dd35cb3df7ffaf28808f4f2e01c4174d78916e9918a2f5d7d25187a5e9e1ae5a7800932a6b86ce4b3789ffc6f6be6ce57a95155ca074f9439de977c6cdb16839010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x28fb349813a4480417c02013be8a706487eb09ac3eafc84cd5f8adb1f28411f67d86a290c699c06ea25705e7552a2cb42b77cc124478568712b02ee87fe2a708	1576355237000000	1576960037000000	1639427237000000	1670963237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb8cfa7881b9e546ddac82b011f3600dc82d347fdf83c7b46d0f84aaa8cbdec1e733eb1bfab507210d08475863104cf6be92c73b89c9661394f1f0d803dd2bf84	\\x00800003c86e22b550e872b39e9a66e6effcdc881b25ef6d460720847e4c5bfecd9524036e421385d12ef4fa329399903a845fb95208237caaad00f56102ff839ebdcf808d482b99a263a380a6090791eba09530a70f70bd37bd1b0934812781723fb35fb0ceee992481efa5afba8fe971087bc6b857048f3452b87fd592e8e361f24f69010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x9aae2e805376f79204a0d13eca4cb147a1e7306d62979306790092b2d863dfc8cacebc2ae280f2dcbd8c5fa531389870cc29787306bb7bced91488943032a70f	1577564237000000	1578169037000000	1640636237000000	1672172237000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5ec53e83801df0d0c2fee937186a203d2956f5ffc9703e3bf51688e5d367260c222db4eb7a4895598bee242e7596416efe6bcadb21cca634a42290bb3c2162d1	\\x00800003cbc87f7a2d12ddfce54900f666d5aa8bceaaeb6895d36fb440f73c2cf5c11fb2173b58a70f3fa061e0862ca0294c32b04a4de444e47196b1f45e9a77e4183253c724aa764c0259428b2275debd8aae8ef26192072b234c0340678eb715913945a7bc418d44ac3b29df2784d7a0ebaf373279197a86e4544e4a3960fa71fd6f01010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x50c300207f9e46a71d5085a7f4cdbae2c64f7d0667b6fac7123e2f8c7f1f52ad64406b3986775cfa5edcef8aa75acc8480d89f1b1dcfad52aa81936773aae604	1575750737000000	1576355537000000	1638822737000000	1670358737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x07cab64f765b1c9b6073d52ab136973c974969df0b58e9ca59fa24285edeceff78f6aa33deda4374687dc4590488ef857eb7817c57e09423823e1b85d8492cfe	\\x00800003b1d5a715583a8c15fe91613a693422f5cb6bf0bd3cca37cfb1e173aa20fe894a954db2f6d73c5139b66b4937b119b49059a2ab89694df084dcc57acb8179103096b74e889fab9c78071e3aea92b1954564b831861eb527fd62b3ddd235be83a431bbe78edda046a04cea08fcdf1af761fcd974e78ef943fa5e95d6b8b41219e3010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xd130b8f6036ea091300aeebe93c67f4cdf2a1b55578ba1fcafa730431f038a87b6c9e84f0408bb9caf2db235fd21fdbdd162a3dc0344703816d6110bafeb8b05	1576959737000000	1577564537000000	1640031737000000	1671567737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c8c0da637ab47f621bacbafd0519561c569e206fab632887dd057eb9e40f47716931e7c41c69136b737f97a90a9d0dec4fd804cd76fa65d50ad7a3061f94587	\\x00800003bd05b15a8a6c428960b9aeb5dea7104c46cddf93ca55afa9ccf8924c6c8227872015d6df9ad0e0826b61b52f361fa729d3d869007e9f165446557cd9400afa9b24726f20e55ea8cfa854e99cb3bd3202dea1804038fb6b36922e104251b15fa83765a57a5a1d58810b884ed76df48afba51596ff8037137b6bb2038c95725d9d010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xc5e881179448b75bdb80f2522c3207fee61bca4873a6b520c7df1d809a587e5da7fc25e2d322c07c550591b037142cf446f5ece8e0be80de2bddb4713a9e0602	1578168737000000	1578773537000000	1641240737000000	1672776737000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2319c6df84541deb9f338975a88961ee2d249dd232a5b436094458252a12620ec1fa37079e6cd6b2c6df9799b96c049c761fa52ce407257cede25192b46bb681	\\x00800003e6d6d898d2e963a849e74ab03ab75107b9c9f32e0fbc770683ffd3139b4a791c60a81af73474e4bd6af73acf342988d2c1dcde43dc64ed859ec72b7b1cf5c6d762a3dd8779b771ef096b7da281c19a7bb1cf027ca5cd72b59e0da6f5599fc1b515842c287cb20a771361176d6ff1d7a9d4ac1af2a6e0e03efedc91db67c1eb93010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xdaa5a4256f5d65f25f1c0322d15696fbdea9427bd314313951a9893c954c36df40f04d20cb26df5d67173e013b142e6383d3e8718c2f08a9d35f25e6fa1ff503	1576355237000000	1576960037000000	1639427237000000	1670963237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xac25341f73d635190247ffbfaa8fd132b2f24c2577cd4b3b4ae0be5696b15948b5247bf1151a1e841b06e25e8260888d493cda748314ab48235bbcbb6fb6199d	\\x00800003ab9d98c272453d730883b82a9d51108278aad5c37677ae80d2b47593b72c69accf103e53db9cfbf454414a5c2653efd0250b915053faadbf281db78d35a69a4c6c482fa102b75cb72b4933026a0da839914ada73e6f52073026fafa5fc6bd48d9a815ba62a0cad807a6c14b167e91e1a10002b9d876b6dff61af9751bc9b1509010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xde8b577cd498d3430b35cf41ca794776fb7934989818bd19ac601f2741dd32a8069ad52e9d3b2d89ec87320b56100812a6df655700b421462c2f5a626c54500d	1577564237000000	1578169037000000	1640636237000000	1672172237000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe39ae110abab976bc49071b955865beef61ff5386b44084da8caed4bffc5003596f9aac5210becbff887b99d0059a66cd416c455ff9584bd2ccd60ab9d2e16c9	\\x00800003a9591e3ca6107927c6fb904696b02e0ab36624aa837baccbcf7168213512f43912c8b2d93badb220385b3684d7291d33d0b1aa214be173f3c8691ecb5ce49503c7383e165222c8854be7cc1ecab055e5bca8efea0bf43f08738d04405bac9c2f47cd643d3c441feed475df1bafa1a0bb80fa55bfddd6adb23b99254e99998fab010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x39bc493a1cf613a114a3501c3f47d61700fba864c755a3205e4b3883cf3f3c27f6e8f53a31216e7895f9d99d2479f49f8e25108563dc516174b4c5ad1ac3330e	1575750737000000	1576355537000000	1638822737000000	1670358737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xced7569d8caf6d437c90e6a49c0c5dc964f164774c279cc09998c60fb7436d5546973212590120992a09af2613498c02d268a398323441563ca9f3c78808c0fd	\\x00800003b4fb5c9b18519ba502cd5119b076d59cbfec41c4b962600a7b23e838daaa928b442749665f1ec9a16782ecb15e8713419dbc3f1e7593646808603a38bee8a658692625f54a54dcb2af98bdf48b47dfb444bbdcc7a643089aecdfa123a81bb78f5e9aea617a4e52b1e95baee7b0bc86956645bd50c84a66b37a1ab71f21e72881010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xbb4319eaa86b8d616281eccca870b2a8bf84e285707b298d3c61b207744bb6adf6a939e79fb7e950f4a4168656840bbdfd203d3270ea95472491720a2d37dd02	1576959737000000	1577564537000000	1640031737000000	1671567737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xae74652701ec321f11f162d2b67709b0fd948d82ef8400e724005f16cc297d7f9271d4af31067b04b3f54f206171f7801f39d30e0c9dedda6ceb8a3425b5c1e5	\\x00800003dc14291fa6ab2327fa9b26d9ae04bf2dbdaad543f73c0224a2b1353de5d37d3d9abb4d91abd7acb44e67a6d44a190497bf783eabc2ad1202f3b193a3c5619fe7d08a1e04e1d4bee10433b4429cdd2eda3f270e8a8a3b9c3f4a069e84778fb25a722e577afaf545413e41c9740348b9be47fe42a525e2572365105e97f4d4eb0f010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x0adbf5cafb548cd24cb5dda7aac9eae20468be2537cc1dde8187672e027d361a38efed52b81ee1fea04bb00dc1fd25c4213ecdbd328fe82f3905ce3a6e064b0d	1578168737000000	1578773537000000	1641240737000000	1672776737000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x24eca5629626491f4ce67e5393a231e8cb340113bdd92e8c881597e2a09ea8f265feb2a77485103b93fd0fea9fc89c9e6d27cd87fbb7b5dfb3f36d735f244e55	\\x00800003a91952d72593df08836c8614db263f9fea12ec226a64636e9193f39600bf475427bd1906070c2a1d184c26e88db29edb5d870e8699c6db5f174176c80abcc6fff0aaf57982f2cc894e5afecce0a3242ca43bd771118bac843e530637289e44670d0a6a7f6e8b08c368183f9b399dde070a6e711045da01e7d4e73884339da6e3010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x5f85d357d79dfd92ff243a620bc29ded10b4e69ea2768766ddbeac451d549ce5dce9e31bf34f0307aff9c21a3edee38c10fb7abed0cd1e1fca0c689f7afbca0e	1576355237000000	1576960037000000	1639427237000000	1670963237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xca8cfee5d6901be3376754a6b73ae49414a88128903ab6bec081456095eed2aff904d5934bfb947ec13f9b5c95ccd4087b732ba2af43d4947b9a8e15f7c41b08	\\x00800003af061bbfed3c560d1686eab81d3124f326e174e34546e0a826dddf32379f9498b9a6ef5172bea3bebcf4dd7b209922f9ad9fee97173b1a3166184f91c6ae15ae0f52354c900ce34043167a759d1679dd342562bb78c794192e849943f22c36ae6b1b6e19c18b62a427c685995ba012044c05ab0338396ae06fa88cac1dbf75b9010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xa1089431d8037085c9f8806180a012fe8db66840707a8a0ae122b0cfa5b0eadc2b3006c4003b4d78d718e69d3d95359a152a53c697a5340c36f9f3e2c0574c0e	1577564237000000	1578169037000000	1640636237000000	1672172237000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x00800003c1fdcc51c852f8a934e13dfecd10d332974e318cf0a48fb939c426f1e7490d5eb1f05b632a33a3ddaf8359add241e5cdc86ed6812186027edf520dd5b197815d0db03221904436608ba7d274d52956424e9da77f479defbadaabd42b19070e2c297f3b1f42155258cb4d2dbc4b06cc9012d6188935b0eaac1c0fa505a4277d3f010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x5b21fceb289ce6366cc49a87c4bfa8cda2157a8009c822d5f6a8faa517057fc111aaf92f1b9464aa22bdc89c8894593d978c9ae0e7585f0b787327df13119304	1575750737000000	1576355537000000	1638822737000000	1670358737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2e35e9f085fcbca5dab777d193816d6c72fc2eace4a03eb48274a0936d8676c4b2b4464b5330a6f887d9d031c8aafd024afa08c0554803ea43974b376dfc81b	\\x00800003cf6403e4437b69be00be90d53c11d9ee2189a3f19b078152c94d9365482ca4fd8417cf2cc34b48386e26afc22e78a47b2dc64ec573105f55953d7515c0ea9d173087ee2b7de9847866e91197fa47f1ffb1b472b9fdde4972c8dfada27d7dfd4354b91ea64cfe414857fe4edf238fd1bae52d4d06a5375cb18090338bcf5a59af010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x8ebf811d0ee9c87ec8f9e7206f5b2b077b429eed8fe1996fc81da483589986e9a78d5efac521cfeb59764524bf2a42d7bd91c2d42d3f852b3f9871c8caf04704	1576959737000000	1577564537000000	1640031737000000	1671567737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5d6e2036de11fa1174766f3cabdff461f1c620d395c61c8d1ca2284a9ec80275d8439f2064284c04dadaf579559a81c05b986d1ad06f297f65f5819f4780b04	\\x008000039ded89dbc2466eba56ffa6071d64f6d423a10d60171880be041d471eb1c61d6cef225012bf86b1dd8d7ce114856b093270c1884847a1ab13e0e16e15bf1c7d9f648e1657f6348660285d2f57d4a138471b99772439a21e534560c63d358739e9829d8e72189eaf1e3c03767dbc3fe7a9a266b5a6768906410964734e0cb05895010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x0a68613eaecb34de12d09ee92d840d5169c8119c8d63ca2dfbc7bc247b3ae4b3b172cc4101279c7ddd2301fb9a0218d5c5c420ff5b74ebf5945f976794b46303	1578168737000000	1578773537000000	1641240737000000	1672776737000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x18a36a8f1de46d0ea5ac63e55b4ce6915e7c792f48f76aba46b65810342899cbe9bc0d46e5409bad6c88e8566cc308383940cadbfedbec2db1fdfdf696b483fa	\\x00800003ab4902e3f054d8c15240b252bfade17eaadb4b2e81ae3507376cf2af01e73370b7a650091ef46b066d757e787b6c7c0014fa7ab8bae03cb2dcca3a3e1276bf53a1855dc8ac771680893616af7558ca54c99904aa504e6ddd59a98822e2fa93b6ce18a6080c398c1d1704307c317163ef2a10c5a6f14ec854d11497e57e407c59010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xc9d709d89fdf2053c3499f745f1aeb703b186942da860c7a44299e0aadb7c4f056d300642045840e454e402daf56d19b01bae2354e18c9f371a6f3285f6c190a	1576355237000000	1576960037000000	1639427237000000	1670963237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0f8207e54fa6d92ed73d2238cce0a1ead4665bd6497a6c32d49fe19a835964ed81d6b76f84a57eedf0166b31135e392453a7ec2794d71f1056a26b2a6d2b4147	\\x00800003db026d3ab3f689f694d40c06a59d17ee61064434d50e07e39d47339906802e1d87a7be875e2d9eccf66e012d121825d72f437c650944dd34f4848538aba25c118b1eb1ad3ad3bdebe81a69656ae7c049523b9c6903870f848ef645ddcf0e120f46d5c45257bb3fb22a88877bc905ea24a4733f64106e39617696c6b1a2841935010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xf6229a393f7eea2243129e5fbca3a39f9fd7c2203dca574f8e923ae37eb9e6bff542ee98d1674335a734381abbd339a18be420645dbabe9c89b1b393a3f4b30b	1577564237000000	1578169037000000	1640636237000000	1672172237000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3002207ec50f8d43f76208a1a5d1bb5457b75297ccb2364e39150bf14a1a38fcd30a7ec3e428366c8fde566119fcb4ae56a241acf1262b3fa4a6407aa1edee17	\\x00800003cbf9da7514edabe0db59bdc3379f68dc3a6c4218f5200ce2dbfad39ad520131c2e0ffc67a3608c89e0ebe220e5dbbee14c645a48e2abfef03cf5d549b6de50fc8f2749ba9f078e0c7931851ea366a9c39c79be35c0ef761cac2855a7f17b7ed2137bfbc0c0a9d290a6f363e831744fb36f26eecfff0d7120d732f10e89bcf2d3010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\x1a1706b54b81524c9aef6629a43830f0027eb23e7e2f468ee77b2ee90485f45d7cd0927063448e7069d1b468c17880c38edbb6e57e2b98fb9bb2dc0770084a07	1575750737000000	1576355537000000	1638822737000000	1670358737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xede80dc88dd843e9defe97134d1596d1ec0a1a12debf9f222b342ed47804f986de7afbff441c26d2c83d9eb14d5b9c312ad114dfbcc47b4b991b5df29590d2f7	\\x00800003d9eabfe30b743dfbdd66dfa8eff1d1d87bff63b0b78462a360d4884694fef1233f262c0f8b8569c60f4be9c11b1a37c119d44e5294d0b490742b819dedbe2a730a70132ed366b7ce40fc716667442edf017bf591aa5da6638ff523fece71344551aa955815f834e3219189096a3049e1de448741427b720a6eb1c07a03ccf6e1010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xcc813599581fb66067ceb9bc371e22f32bfe7d631b3647406b69bac529fb2443514f4b018d54184b5ca85b420d8006d3ffdd3ba2a886d18e6c6e24658d712704	1576959737000000	1577564537000000	1640031737000000	1671567737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3d9e8747b44b0e417018199780c43653a645f147c42f6f48ddb6fb33b13b0e95ea34363c7a2296e1bd1615bdf1ecd15fba42d9eb2dbba3d6fbbb30bc972af603	\\x00800003b3c3ecca72975b70a55c53f3e6282caf73afaba2e365b947c88b6a3c2d6ec5c20efb08e82480ac65f1b7991c9344ac8a95fd1fd166d629168c670ad1812215b04f489c3943fe8d4928c9d99d4e46b3e2550a48a46f397eeb67c8f2cf08fddc9b4b5f491e74f9a57cbd6907a6dbe2f12deacdd5e3a1805bb47e2e124912557e01010001	\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xf5a19c805582609dccb1d41777b0a82a127b30aa40dab8bbb5325c02343535639c39cdf9e50e747389ac65620f4b2f0f78398e64c6bfe6b40a6efe74beee5103	1578168737000000	1578773537000000	1641240737000000	1672776737000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	1	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\x7ed83656ccc356af26e1b4e0f77a919b58b235580ffbca0ac7c423104e0f2274	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x75efcdd9e71ca7e5ae39bfc4858054d3796107b689ab614291659dac41d744b489d42f7d56f175d431073d4cbccf42110f4c3e7fa7fd0e831071348c7ea85f0f	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0154eee227f0000d95e1957ae550000890d00d8227f00000a0d00d8227f0000f00c00d8227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	2	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\xf51517b7d13e9dc0222b1ee95dac3cbd034d0f82aef1081d3b7534812cde311f	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6a5079f6c449619f998550799e7d19475d9b346fb4ba76dee4fff875f04d251bdcdff7ada35137063e13a1608fa0aad5bf8cc64ba737df6fddc288fba713480b	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0c5ffd6227f0000d95e1957ae550000890d00b8227f00000a0d00b8227f0000f00c00b8227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	3	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\xa579ca03dc84425d3b3081c286f86fceda25695f7f43ca3d6291ff1f0dc50d1d	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6873a7063214d75ffc497328d43bd899b9f8abcd35d0d29a25b0e8409b52444e5f5c9a65be843e32ce834c0faffde7813271e6fdd48f67a229af5b74c61a150f	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0b57f6e227f0000d95e1957ae550000890d0058227f00000a0d0058227f0000f00c0058227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	4	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\x9cfb5d7763fe61716137d2d6b23bb37a5fab1fac7e43bc98fb9b36346a85db90	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\xb260b21f0ddc832cf7338c5b0d717da2020a40841f26bf29bfa1efe392e2a1496d314d09c9cb6e1eceb6198361f686605486dd1120507783b35b499bca76f207	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0a5ff95227f0000d95e1957ae550000890d0078227f00000a0d0078227f0000f00c0078227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	5	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\x53e7f5733cb34ec1d383de8e16fe9ddc53296d619c7a4541904cbf4d94b3a286	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x97bd04aefe2ea016e6cec21e01de2c22c41d33b1f8bb2de67fe1fdb56a4314d8e730ea3181d6ee52b242f74ed9b7b983df8d72547c4952f135a341724a50bd0f	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0a5ffb5227f0000d95e1957ae550000890d0098227f00000a0d0098227f0000f00c0098227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	6	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\x2293a6360931dc22ffaf0247fa49d3d486abff2e0611ca2316e6c7e23a88848a	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x720d6a82e4887da63857a099b10b1bbea87985349b6f81e3c21f4eb6200716be1ef53784ddec615439362d555f5f1e763f99abad3971921086f8b05fed98ed0f	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0d57f6f227f0000d95e1957ae550000f9a40060227f00007aa40060227f000060a40060227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	7	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\x07d941da9e88aaada1001458732820fa4b2ace773307ba9a2fd3d9f2be533274	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\xdd18413025da02fc3b0089b783e07e50ccc666c3485dcf04578bbc81d6e2c1eea287646119515854c1dfefe9059d30dc81cba0f2dd08d54277a19a1b75363607	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0c5ff6e227f0000d95e1957ae550000890d0064227f00000a0d0064227f0000f00c0064227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	98000000	\\x7af1e51dce08ce93a4fdcd72f72b7599a6f3a802ca0d8c62df3d4fe1e8a2cb73	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\xbf1a06e4a1fc8716aeafeb955c3c27a41ae7812cce6f37fe5fffe135c780dca0b647d9ce7932cdb427e96b3ab019bc4d229e31c991917b9e83c8ae7410248100	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0354eef227f0000d95e1957ae550000890d00e0227f00000a0d00e0227f0000f00c00e0227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	9	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	4	0	\\x24485d3ed797fe0002a71b7b6f5e25949744bb078a752c647ce421311e15a3d5	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x5cee02ddc4137d34aeba97379bd025019a67ed856f5c31bcf760d4fd858ce3591586333f66c14f9b77c6d48002f66fde7e7a18838e9cd08857394723a9467108	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0e5ffb7227f0000d95e1957ae550000890d00a4227f00000a0d00a4227f0000f00c00a4227f0000
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	10	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	1575750751000000	1575751651000000	0	9000000	\\x2336fe01a7e105b586437013fe01f21de55fe9c77e5ef101a67e643c272a1fc0	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x1f36723004989fb3511127ba18b013e54232a079cc38ec8be4d6e8628df7ef03745209b0682511e2c59846f9a59ee48f7ad754e5103e6c8f33e3ee2514866e03	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x16e50df1227f00000000000000000000f26c02f101000000e0e5ff6f227f0000d95e1957ae550000890d0068227f00000a0d0068227f0000f00c0068227f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x7ed83656ccc356af26e1b4e0f77a919b58b235580ffbca0ac7c423104e0f2274	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x1ca9e621539b7400bf6b73dde150067898d77bf67073f6265c13183beb5c5ec9ef65d378e6c3c93fa2b11b282d1d303da4ee6625664a723de5fb7718b8d0640d	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
2	\\x2293a6360931dc22ffaf0247fa49d3d486abff2e0611ca2316e6c7e23a88848a	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x6de94e97dbbbd297cc018cc06bf710caf6738b5e7ac9ff9959d48ab92ab3edf1899c177a2702e1d1ebbc9d024a8bf0e017b7a38dae3a2a853bbbe87a7cc2930f	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
3	\\x2336fe01a7e105b586437013fe01f21de55fe9c77e5ef101a67e643c272a1fc0	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x1f6b2d8cb14ce212f0ac1a60d4140a056e6e34a3db2368720514d7905574fc2a278bdda376c7cba1b65803eec86a591ef9293e596994068f388146db26327e02	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
4	\\xa579ca03dc84425d3b3081c286f86fceda25695f7f43ca3d6291ff1f0dc50d1d	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\xe70cfee834f8147a493695986a3fa3eb9ec764434feeb0dc759236fc9c0d4e654f8dd7779d25f0b2cdd77a04b88cfc318c90da95b6f156ad0cf9663174ed6a03	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
5	\\x9cfb5d7763fe61716137d2d6b23bb37a5fab1fac7e43bc98fb9b36346a85db90	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x6f2b72f1f8ae1d94c34f5cbcee462162f1b9143387b7c41ade4186d0347f2f4f237a7eb5f09e638788f43688159bfe9b51a4d40b6e8f7115c12dc8d2a0125505	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
6	\\x7af1e51dce08ce93a4fdcd72f72b7599a6f3a802ca0d8c62df3d4fe1e8a2cb73	1	0	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x4e678033e3fa1b88da82b252d9db793e41bf8765857d7e90cf6280e2f9fcf7421cfaf603a47aaadb2dbdbf1f50c035ff11c225cc3373916afe0b538c1009bf0d	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
7	\\xf51517b7d13e9dc0222b1ee95dac3cbd034d0f82aef1081d3b7534812cde311f	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x4d2cd81391f6619b498962ed8b47a6cfaa4131d1cc21b4d55c0ef8059400c6c457dd11719e761604478f30fe32a4fb7173f963aa241cf91f2bb5ee17b7341b07	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
8	\\x53e7f5733cb34ec1d383de8e16fe9ddc53296d619c7a4541904cbf4d94b3a286	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x79e251827417e40fc180ce9d4e7046c188e621b37cfefcd2985b319b9195335b61d373fbae793c2f7b6db425744df4450e21fa6575f4e488941dd80494b94c08	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
9	\\x24485d3ed797fe0002a71b7b6f5e25949744bb078a752c647ce421311e15a3d5	4	2000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x62bca70c1abcba271560836175b40e849302f0356f99a64a739023143c73eb7b656e7e89d95bc08ca3c5445e608f3bda0678524d2e23a4750da5aa60ea53f602	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
10	\\x07d941da9e88aaada1001458732820fa4b2ace773307ba9a2fd3d9f2be533274	0	10000000	1575750751000000	1575751651000000	1575751651000000	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x61c93605b53513b19ea2c2629f00c6f0e8c378063d9d5d10753f1572d272b80970d123be19d4b07fe08d67ac722b4efde2bef6d2780570a00fe72f3d696d2078	\\x291be94c78db19429b84f2a8e1e4dabd03901a2607d01095adf9aae831787db6b9561539e134c4e774239ee9f9d4049d08022c76ed7976e4b9eb701f6f5efb02	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"QXKDSPEHD0QHP35BASDSCMD0RXJKZTW9S9DZBRG8V7TXMWJQX7QC2A2J8FJTM66CSYGWP10QSRW4DVAZXVZ9089XAPKX2H67QMKD4A8"}	f	f
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
1	contenttypes	0001_initial	2019-12-07 21:32:27.651544+01
2	auth	0001_initial	2019-12-07 21:32:27.674335+01
3	app	0001_initial	2019-12-07 21:32:27.711785+01
4	contenttypes	0002_remove_content_type_name	2019-12-07 21:32:27.732187+01
5	auth	0002_alter_permission_name_max_length	2019-12-07 21:32:27.735652+01
6	auth	0003_alter_user_email_max_length	2019-12-07 21:32:27.741132+01
7	auth	0004_alter_user_username_opts	2019-12-07 21:32:27.74596+01
8	auth	0005_alter_user_last_login_null	2019-12-07 21:32:27.751027+01
9	auth	0006_require_contenttypes_0002	2019-12-07 21:32:27.752113+01
10	auth	0007_alter_validators_add_error_messages	2019-12-07 21:32:27.758219+01
11	auth	0008_alter_user_username_max_length	2019-12-07 21:32:27.767063+01
12	auth	0009_alter_user_last_name_max_length	2019-12-07 21:32:27.773294+01
13	auth	0010_alter_group_name_max_length	2019-12-07 21:32:27.781759+01
14	auth	0011_update_proxy_permissions	2019-12-07 21:32:27.787597+01
15	sessions	0001_initial	2019-12-07 21:32:27.791926+01
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
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xd43b827b1032e18f1df08769f48ca95a498676825976221470e29259728efbb8e31a36ee26f148cd088e33d4009766bfe2b18c699de9ba7c8916ec6ce4c7b300
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x2df7e9204c2c84c285d7ab17a01bd57f5766c111855b83a712580a230f0e0852372ced6f149a5ffda92ef847998decadabe633539272c67bc343ede556e9860e
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x6a35e92bf70eaf293daada648f908624d2ff1d835023465b67dc55d3d208a62e960c1d0ef7620d6136bce7b509cee2dd6294163609d1cf7df1800de2e2629301
\\x415d37f48bbca707bf8d5742bc2ac67600b1ab7ed0044c4ea694b7a9f90a465d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xec3e83031702287bd45e6a8a3e00eecb7fb57abab9fb5e1e021eacd0129e639c3da5dd8dc2d4316911978df53ecab6d66a09942865b2ea59fae85539c0464a0c
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x2293a6360931dc22ffaf0247fa49d3d486abff2e0611ca2316e6c7e23a88848a	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x739761a5fdc36382a27199e4569fad83939edf7e2482cba8c9caad241ccb211577e9c11cd06aae954a25253cdd7659f4faf880a0ca609b17a2b139e681831c135d47141d78b2a8429ce975285eb79ffb27cc56c9df45d7777963a0aeeaf9c7e54b287099c6b3d7e0de9ce12069fe1c9250bf9e48ad6b3cecad91b71c457706b6
\\x2336fe01a7e105b586437013fe01f21de55fe9c77e5ef101a67e643c272a1fc0	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x02d3aea93ddbc3010c15562a3799e5eee304bec69995c043d26f97d9f252154a572350b80ffea5f1eb7cfd752bec012edc1bc4fb9c18deb2b27fcab6c535e5c31803271b9d29f7295594bea1e23edb8528fd7211dfe862017a88558173555ddd0f7ae9ca118a245816ce235937e7249bf40784d066a6fd412aabe194b2018d50
\\x53e7f5733cb34ec1d383de8e16fe9ddc53296d619c7a4541904cbf4d94b3a286	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x91dbb10349c6a739e80c86519467fa0ba71cde5576c77b01a5622188ea19c869c42a0e336dfe3b35df18b03c5c4852e8d1b5b714a3a0609ef3ee739cfac4361609a0dbff67dc3d27a2136c5c6c26d7dcd3c70886d96965adbf24fa230b1e53226870d13a3262ecae48e8557319e133cb9ea4ee41354bf73b2babb7e749f1c702
\\x07d941da9e88aaada1001458732820fa4b2ace773307ba9a2fd3d9f2be533274	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x34a6e033cc6f721decd3f0ab03d5c6e336a86e96b399d11ef909baa197e5f09b5e868edeba5afd3a689e928720460f8ac25ab9804de8181f370e068442ebedce36d3f6763483b98e23d42c0420ae5d9647e1cdbb3c069d013a5aae958c88013323f58446dc299a5a44744df1eb162e9ecac6ff92fd0d008af65cb2ece8c7d310
\\x9cfb5d7763fe61716137d2d6b23bb37a5fab1fac7e43bc98fb9b36346a85db90	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\xace02ec84ce1110b2678f2d82d35837adc12aa66664b864fb5adbb8d7bd86bbbc502ce4438f4d1c164a0a4a1c9775c5ab58ef2213eb061ed40fe82c272d2fea37e8a625983186e5b9fb1e1a7f8f4cbd8bbc62c90925287876001e01541da60120a57d8440bbfba56fe6095dc9ec037a3345c11fe7efe9e4c7c1617f5b8eabf86
\\xf51517b7d13e9dc0222b1ee95dac3cbd034d0f82aef1081d3b7534812cde311f	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x829e848f13160902400c9f6e1bb23a1b1646d4c783bf2ea5d216c2588f95ceb0cd20cc5372ce33e2900a4d911bf6933769fd04275f2472cd1a4990ba5f7aa7224d46dade554a0ff4f2702a8262af983f9960c9109bf83c61694b600313b3ceadb2dc7c662241c22b1fc141ce0111d9f1f2e1a7ad564451c89db13be21049ed50
\\x7af1e51dce08ce93a4fdcd72f72b7599a6f3a802ca0d8c62df3d4fe1e8a2cb73	\\x5ec53e83801df0d0c2fee937186a203d2956f5ffc9703e3bf51688e5d367260c222db4eb7a4895598bee242e7596416efe6bcadb21cca634a42290bb3c2162d1	\\x26b75bc0c4a66534ad39386b1a7e014a27735b60b2835159ddf0c6526c8ef5086bc2ffb45c05e801b65fb9a0fdfbdc134c98168553acd2fe6ff5e06a708664225cc3789a90c67840509dee09a399c4a978fb146f221c966e6a9c6da26609b4f7d9f1909c8d4f6585d18297cc585c12a18f97100227c38775d4787fcce36b8c6a
\\xa579ca03dc84425d3b3081c286f86fceda25695f7f43ca3d6291ff1f0dc50d1d	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x57532f09b2e227b297c991b5af33fa59b988974325e4923f4ea097bdba38cf1f9f147d7fb717abc7abe5201eaab8629b899d6c1ec8a4e6d53051d81d338f15e8928b7b519a90bf33e0aa000874327eb56adc6b820e7bbfcd296612a6570027ede05ffad9467845095083c906e4c177ea69193162196efee8f7ce0d572c691896
\\x7ed83656ccc356af26e1b4e0f77a919b58b235580ffbca0ac7c423104e0f2274	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x4855d41c30f90ff6210190e5a7a809059ed818e4558ad966e0f4da6d0fc98da040077c4d01bec42db97fc8cd13dad131f44b0e546e25103b3e3c3e1ee2429a16a7e2fbd7e89d5732bccfd9be1049eafe46bfabc8a5814b8e06c76dbbb77e02de8d138fbd763b1cacbce3104f9f5fa084a8ec0ef605e2e54ed27d670ffc085bb7
\\x24485d3ed797fe0002a71b7b6f5e25949744bb078a752c647ce421311e15a3d5	\\x3002207ec50f8d43f76208a1a5d1bb5457b75297ccb2364e39150bf14a1a38fcd30a7ec3e428366c8fde566119fcb4ae56a241acf1262b3fa4a6407aa1edee17	\\x76211bfc1f37d4471050ddb8b9ec4674672160d9e9a7b07dc4c6d333b05a329a30bb91a9d02f691ae2af142172bbe91248cb324c8e3cb3f302ef598f8f5f034a5349014a66635f2e6250f0021f0bfac0a4e6edc4c72ecc7f477f3a66217fcf2688da70f4a3d476c67ecc8ab6cbed57d8f12c5e26991772f6a2e737c19637093e
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.341-03PBSXA2EQF7M	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a222f446174652831353735373531363531292f222c22776972655f7472616e736665725f646561646c696e65223a222f446174652831353735373531363531292f222c226f726465725f6964223a22323031392e3334312d3033504253584132455146374d222c2274696d657374616d70223a222f446174652831353735373530373531292f222c227061795f646561646c696e65223a222f446174652831353735383337313531292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223835454b46583442514a4b47464657444158314252415036455230423341565954303234524b4e364a4a56544b59384138534547227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224337344b4331444e364d395633374e32523948395930363659334d43365930363750454e5434334e37574151354d4b4a51303451314d3933515243583943335a573236504642334a3544374656524e5959563937473142474d303759454253584435504a305930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a223536544b47424347584e584a4750485744315a3758534257333951323837415a335a444137313044375232385356563536564330222c226e6f6e6365223a2234323037345243304837534843524a533652485456465a4b4b48424a43485445445a305a5347543153434337594b5a4d52454647227d	\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	1575750751000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x7ed83656ccc356af26e1b4e0f77a919b58b235580ffbca0ac7c423104e0f2274	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224551515756504637334a4b5942424853515a32384230324d544457503231585048364e5032474d484350455452474551384a54384b4e3146464e42463258454d3634334b544b3557535831313233544337535a54465a3845474338373244344346544d35593352222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x07d941da9e88aaada1001458732820fa4b2ace773307ba9a2fd3d9f2be533274	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22564d433432433135563831465245523048365652375233594133364343535033393145575931325148455938334e513252375141353156344334434e3250324d523746595a5438354b4d5244533045424d3353445432364e3839565433364756454d5633433152222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x2293a6360931dc22ffaf0247fa49d3d486abff2e0611ca2316e6c7e23a88848a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22453836504e30513448315954434532514d3243563232525651544d374b31394d4b44515233525932335837424338303732545a3158583951474b45595252414d37345632544e415a42574637434657534e45504b4a57434a323233464843325a58504345543352222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x2336fe01a7e105b586437013fe01f21de55fe9c77e5ef101a67e643c272a1fc0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2233575637344330344b324656364d3848345958314843304b574e3133353833535347574553325a3454564d363533465158573151384d473950314d324134463252504334445944354b564a3859595051414b4a4830464b434857535937564835324a3336573052222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x53e7f5733cb34ec1d383de8e16fe9ddc53296d619c7a4541904cbf4d94b3a286	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a595947394251593554473144535045523846303351484334423231544358485a32584a56534b5a5737595641544a33324b4345454337413636305844564a4a50393146454b5053505957523751574445394137524a414a593454543647424a39393842543352222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x9cfb5d7763fe61716137d2d6b23bb37a5fab1fac7e43bc98fb9b36346a85db90	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225039474234375244564a314a5358534b48484447545742584d3831304d47343433574b425941445a4d375159373451324d353450544341443137345750564759535456314b30563159543336304e3436564d384a304d33514745534e504a435653395646343152222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\xa579ca03dc84425d3b3081c286f86fceda25695f7f43ca3d6291ff1f0dc50d1d	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22443153544531484a324b424e5a5a323945434d44384559524b36575a48415944365138443536483550334d343136544a384837355951345443505a383846484a5354314d523358465a514b5232434b4857565958393356374d384d545950564d52524431413352222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\xf51517b7d13e9dc0222b1ee95dac3cbd034d0f82aef1081d3b7534812cde311f	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22443938374b585034393547535a36433541315753575a38533858455350443346504a5837445151345a5a573742573244344d445853515a514e50484e3244523637523954325234464d324e4442465743525335544544595a445a4557353237564d57394d473252222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x7af1e51dce08ce93a4fdcd72f72b7599a6f3a802ca0d8c62df3d4fe1e8a2cb73	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2251574430445335315a4a334844424e465845414e524631374d474445463039435353514b465a4a5a5a5a474b42485730564a4742434859535353574b354b444d345a4d5050454e473336593454384d5936373453333442564b54315748424b4d32304a38323030222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\\x6bd8d5e5c90773f9c1e972ee948a2bb7b3ed605b9c2b3ec40517f8c0cb8a8a06e31d5f72a8e2009320746d550ce5adbc0fd9a34c337b88461fd7ddcc1f7548ef	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x24485d3ed797fe0002a71b7b6f5e25949744bb078a752c647ce421311e15a3d5	http://localhost:8081/	4	2000000	0	2000000	0	4000000	0	1000000	\\x35e9d6076e0d0ae108cb69d1671fbf3549d5d194d9bdf8d617aa247b61dff591	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22424b5130355145343244594b39424e544a575653514d3135303644364656433544584533334637514333414656314343574443484231484b37584b43324b5756455a33443930303259535158575a4b5433323152583736474831424b4a4853334e353337323230222c22707562223a2236514d5843315645314d354532323642443738504537585a364e3458424d434d5636595a484e47514e384a375052455a59503847227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.341-03PBSXA2EQF7M	\\x29b5382d90ed7b285a3c687e7ee57c1a6e241d5f1fdaa3840d3e048cef6536d8	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a222f446174652831353735373531363531292f222c22776972655f7472616e736665725f646561646c696e65223a222f446174652831353735373531363531292f222c226f726465725f6964223a22323031392e3334312d3033504253584132455146374d222c2274696d657374616d70223a222f446174652831353735373530373531292f222c227061795f646561646c696e65223a222f446174652831353735383337313531292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223835454b46583442514a4b47464657444158314252415036455230423341565954303234524b4e364a4a56544b59384138534547227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224337344b4331444e364d395633374e32523948395930363659334d43365930363750454e5434334e37574151354d4b4a51303451314d3933515243583943335a573236504642334a3544374656524e5959563937473142474d303759454253584435504a305930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a223536544b47424347584e584a4750485744315a3758534257333951323837415a335a444137313044375232385356563536564330227d	1575750751000000
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
1	\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	\\x24485d3ed797fe0002a71b7b6f5e25949744bb078a752c647ce421311e15a3d5	\\x23d9165ad52175e3412949367f69a4f9aa31a15ad798dfcc90987c29886dae24f8df1ac51ecdf2f208520f8ec620c1253161e3cfb4dd0116ceec07566d63020c	3	98000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	0	\\xbda0d05d2db315f8cb812af1dc2f74d406e32c65eac0d6d39323a0df31a8177d246bfecfbd24fd36968c99e1d28c73dc3642a8a24761600254d09bab92370403	\\xa06ade8eac05664ae4b3d8ac5775b4efbbb4520cccdbb5b75d172e26d718603095ab2c33f046953127e23a3d1f1b071db864871b5ff3f89c27ed16aef96ea2f3	\\x99dff2c738f6496f6c36883592f18f93a2c00159f5b23cb2aa7667b74308a7bb55034d5bf4ef451e388d0b749c63e3044e3809f84bfc45320c054b56037614f4b16811d412a0e91e62f9a4ba73b3afaf6ceff59f600e4cd80dda5419af8c309975c385632b7a5185887ab14f854bd83703d6723d7785cf1d9070f03f825102cf	\\x932eb6df255850ffe662f3ee11d1555ede39066aa290126aa6b7167a20f18ddbfb60ff243b1352f62427b083dabc0761a10edd8a9acbff474f9e6849809205f7	\\xa135b7b52c1b2d7446c30638f9cb5f7866dbc4cedeb2045ef1cc03e77db77438a83ed79786964f674c1a16b92fe933590b738cba991449c7f50b06bce21702b17514541a792a62b923e0b0567e4d5d0c5b043a327cb2890b65f1569337d27bb4549ff12b0bf90b7b56db680268abb79449a7146b779183a1b837c9a15005270f
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	1	\\xc4addd8488388602cedd621fa48c7a0e0af1acb7e27aaa1f98a517c2a467f75a871aa45b3024c0452a37b496e6ae71ae91589122db760c58602e9555f78b2801	\\x5ec53e83801df0d0c2fee937186a203d2956f5ffc9703e3bf51688e5d367260c222db4eb7a4895598bee242e7596416efe6bcadb21cca634a42290bb3c2162d1	\\x14442e69f896fc3b3a9d2ef78a1731e9194b9d007e61b8c16a85ceafed89c5d077173f83a10a9da3d3f1b9181f7270ecbc2c52b5d7c627b112ef1306fdcf6563f71973873fc203a25ad2499c68efa05dded02d6e63c3e11db651d38fad6f4b9e08add0cc077c1d4f1cd71b6655a0fe5585dcf6bbaea158cee65efc68aa2dafd8	\\x20539d64871a5d4c0bdb2b59a2c91167abed9906b48a29ea9eba94a7a549e2f827179ee20e21846636ff87fd37b5ccf513f4cdddf071a6706f356e3207b566f7	\\x8671bdd1b3a5a71f80e8e19df2e658ea0039136dc26267c817ce02234b7f32aad327f0757ea502f550084d70614e8f48cd23767279c3da81a1dd9d65ab7cb33e9ca012269e3b1917fea595cbafe5f22f1a4c95074dc0a8c63957e1e626b6069b9e703fdcb04a7d5eecac5d885913484a95f7fd7e51619704f03b07b3389c3b31
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	2	\\x685b3eeebafbe9670ad8a4bf320ef3adee5c7839deef710d77b94b04b7443225cc169cd46f0c4a6b35d7dab29993e5710ce9f14b72a4acbe413be0eb20d9b10d	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x5ec0ef99fc3969a737752dd7aa2facfb1beefba0225127c44a7f916fa1cc1f07b1c50719c94b6b2e3d34a10f8eafcb6eb1ce7951db92a6d6dc7e2fca763ec2e74ef0053432a755b4a86891f76b4619c9b3039dc1a95787d7f528e6e82895744cde3cbc14a0b80ae44263de09b187102df059b0695ddc953323122934106ce2ff	\\x55038a6178ff51b9f6abe9dcf94a7486ba0ef175efa919b820be2fee3e2f299c8aee2b63658d262d8f5122cc8b0a5b9f726325bc7afde382acb383c59fb0d5d4	\\x30e696dd13f889ee4e8418d5c0babb068066e2759543e069c463e21b5d70a0c1595e5b5c25516d511bbc94a4d59c458b20c4cb7b3dddb6e43767da4a90e15bd9bf2d34e2b88180099f47266d91b9ac87f8629f3658ff9295f0d22bdbd0b21154806d86e75bf4a437f25cfb056ebb7531e52a5cae2999be4e0fbcf611049c2464
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	3	\\x388cc852e517ad73618ac4b4d2305330f6966b79cbcbffcdb65572e2a0f04e138fac5114db37148fdffe629ba209fe9ce6590841ee82f1255ca26f78bbf9320d	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x1627d88e6f8f82a67a854dd1051135ad0ed027d5ca0405237f9a054635c2ed6104ccfa9b84efafc33e7a7d02e5b7c04a4108e68237dceeb50cc42e9d4d4313e54d6ceccb16e8e0457ad57eee4a7d706b8b52bcfa041bdff47c7aac951c3890c5ff6fa8364823cc9a7b39f04ff76cf00763f65661311a9bce6a2ec367dbe15006	\\x24600e429fdabb06fb92c225632a7e0033aefb33b0867198067f838899448da0454795971a19eb10052bed46c56c3f3c1f1796e5c834a160ed592146a4996514	\\x2db501fd74819ff7237ce231f7e390aec8b9a626f81333c4018bb7778a3c311ae0ac87effa453252b27ec094781345063a4fcbec19c893d8e465d0aba7f48a3562abc082c6772f1ef72761955766776490fe08068ead6461b86da75526b22912fc299f8bc6cf6624af91dbe4c1f5af95e2bbba28da6542a91edaa142e5ad451e
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	4	\\x816fb3305cd24f3be67e46899075b8bd8f2da371ecd25c7b6e30c1eb223fd24895c279f2716c5fb4c922097d1f0694ef2890144f7c87cc1068f3d74fe6e46f05	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x2bf5cfce46629ecd289acbe7b10da6054a1b41ba373580030611d9d82639d4cbad4fa915014c1e0338021f06f93e71a8be0adb74049c0b905760cf9e2ceefb58bc3bc000156f66384b368f22d4cf2e206400f9db599f10284097e7d9da660ebc6717258ba7628897172321c22154d7b99c659914dce194080a5edf11df986b07	\\x928181b6451ee36486404461e149e2c141480576f3ee7a81483b68f6315f93cb57a459173474b22838350a0d52788bb78277100263bfdd5f6639ff0e5659d98b	\\xbdb39e9c916f46dacd98a595aca5adf7df3a9d5f3bf3810a7f1be779e2a86371c0b0816bbd24afdc13e49347f8bae7c0c65c2cca1eaf675b5771175d03c06ba3f4ab5b7d0fb461578810e67ddca45199b26289367ab6b62681e287abf4b693bc7a2c6d893c76997f093a35d1f4ac65a1f2210fdec4e11a63a7e85afb6709da4f
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	5	\\x0d0af7da9b75b5c924ee193b1a8e0746c740b2c233dcadfa552f7ed436b8612b8e3f9b80a3e24ba035fe61517ed5e3715589a91b104c5ef52140be9443517909	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x109a800a474b4f58630f6bd69119c5180c12ee1fbca15b9e40cfe4bba810ef19248962fdcd6ddbd6f1f4ea7411b69a7718398d794b851a5d3c72891e81d419abcb21c38c94993c7b5b3da15a38b4fb173cf5a667ee60cd3a8eae5a95a2c6981fd4e9bb602e66f61b6e4bfa02172820ccadabda4fdb3a5f4b4f8d9d5905e1902d	\\xe77d16b9a6b1cdda0b896ea99e5ca5a392d39fa0227516084cfc496be2c4eb836dae7b02ab65303be790d3130a1ec7491f0d311396b0e8584cdc9851111de889	\\xaf2fe990273c50f02b9f10add87abe5203251aede7bb76653225cffc0d1ccfa254946fbfb79bedd26b98e4b9093239f670402caa21365e1b9465c8b4d0d096512b167edfd7ce928ff639e50bbbe714158fb4bdb563bd469bf3c37b3d8130de1642639b728cf54cd30db61a6d0a5954e7d4b07edccefc25c8279762b338531bbc
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	6	\\x0dee9abcc2c2791fb7c84a32f4562e0ec2ddc3b17bef3a263602de0fa9412ea49aab823a8d67ed926d700dc1bfd6566bba048b559ef99a983cb3e58c52bc170d	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x66da4be6a3ed23d3813bc5a75e900cd954cdbef0643774c3a335a4d418b1072c9b6d35d6119dff594877fc23d8dca2e8515390000696e919bb371333a5c19ce1ed02fe6f6957ab743c18527288854b95e49df229b8ca53b8f839924afa2642a1599604efcff1d931ce706eae5c876c9ced1aa6c8489daf3c137eadd731ad2aff	\\x7584ccd9c0af6c60044cc1997177bcb8373ee6d0456f02b967ccdb34f47f47546de0fdd95108b0b00951fbd30a84d4699e75a45b75bbe96f12139ba63ba08f22	\\x509c4697ac65dface8b6efece4960e7cab6b2ac768963722298d217eac2239730aabd1f69e167c7a61ad0238d5118996aa898622af40032c7168eca45ff445579272df8a45387533eaa7ab30c76a4f5583b0f886341ab1d50186ea72a49260b17f1912789e1ad812bbe704c131ec0e310d63b0e125ccf4018c385b53296be72d
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	7	\\x553236908f0b860cb0b37295ba1f20cc60f64ba17a7ca86d34ef746ef6c791663005a666aab8f6bfcf7f4df4cab0d1740406693820d55b86becc63fa00604103	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x1b8ee98a17b17c14926bb879aa3ec35482dfbf428301adafb4a6e31a3d69f46accaa6a4b3865e857e6473445e0f57d6bb5572f2da8e31303a150a50c92bb5711d93730befae241f501a15f35496370302efdf7e095f9e1f441ac80ab1e184ad82cf1e126a518b2b375c36947b384192a7f88ff062c342693535b14c18f46bcb4	\\xc71f9926317e36df103d5536a99529db1151d2e495eb30e976c0e8acdafdbc05c4029c1631550714563c02543e5bc620662e93ad7b818853642ca6be239a9833	\\x747403e9a2320e464719f92a87279d68ffae8a5492a03948bf471813edfb6b78dabcecc346de84cb4533a3c034c526ce2ba625ba80bcac9bf6625fbaf85f286daee687055355feac1260cfdc9b4ffb76b588d43f9331059847570857363cc8c1839205cfb6d9234c0918d1f83ffb0bced9f9c0d4066820ed2d8f0c3dff13751c
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	8	\\xcb7ca857643cf4e060b6619046dac4eb94b3a7ae430d8b0da46aef1c7dca2494f48a131c7232e7942b8a175e49414f79ab4f666de16caf7382ba3b1d54b5a305	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x6b8dc9ef7d4f2ba0d0e083cd7fcee5fd12cf76f33f63cc2d636b870cb6dd4b2113b317d0b54373c7c92f1632532b63b607098e768925b09706af607bc22dd22aea591313402d7d4b8f74a4d408c9584042955e89cb76672d725fb4b0a04b9f912c17c1a6a4b8c00fbb14fe72d6b1cb2e66c8b25824e600751429f3016deb693b	\\xc2d36fb866e7f5f6a8a8597060bc72211a637f1fb082af1be7d1ce9b5f234bfc675bfb794587d416e1ebb1b5ca4ce6e3ba5ff1f0ad193166d16ab8e32ef25cff	\\x88de1a1bde155337fe2d7c9555b20d29bdf55e9dc5eb2c80d66b77c6b28d391baa70c30b2ff58498098bdd9be90f1e7d380d5dd5ef0c73c546f17b1989800e831153e275ee5987f2f05ed411681259ac3952d4f19516c3f3510dc630aa9ec79e6de0febb655a0f4a93a8fb9570d03b164d0d46189064a6cfc60f043822937cc1
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	9	\\x1da7287295249dc7cc7c6247423885a9806e51f87e5329c1620a441ed009caa7164cbe71d9aaf8cbc0011eba8505333d709079bc81250dd9bd6e44db92e36e02	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x75c57f6d11c15b7bcefc785a608dd69e3bb269d432e8e2d7832028cdc38efa513f1b6a56181ffd54d27b4330930b09e022bfb4381ac1823dc530ef8e1f32ee2af805693363762270929f9907841484a139f830e8baf00573e8611598a599b3842b38cec3ef06b7dbe641589b1fff06ae488a31d76fd38ddfd9b887cd6209ec03	\\xcb5f8d2030258e2e83001d135cb95396f54333487c4caec134239f54466b4ad74147cce0574bb2a7fd56eda254d5964c63a3e888233a5d55fb2970d45931a94b	\\x389327a838a70e3cc9be15d1208fafe78df52c543b431da0eb6b08f667a358b2296832421bfd4355446be4152d2b77e171be636d61503d75bb09c827b746fdaf13126061042133b45ea938b7579654af06ba3caaa4a4844189ed87276b1bc602b9eeb8726afcad56b97d76e9f876439f07fd3bdc9c472a0de0b8acfb9473ff7b
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	10	\\x04e52c8e28d58707497ffc6d589f8bf699e4a2bd8706f790670d5fdced72bc23a73bbcb8c662a9866a8da66adbf3e8fb59d630f65efcb210cb5c3849caf4c408	\\xe39ae110abab976bc49071b955865beef61ff5386b44084da8caed4bffc5003596f9aac5210becbff887b99d0059a66cd416c455ff9584bd2ccd60ab9d2e16c9	\\x2ae91c9cd6674864d07bce52501d0536db603564f7ac5d6daef11b6c6e9f430894ab0bce304cc9292e896f393332cc9068530dcc3fa989f35c6b373d7daeb829b47dc475578bbe6290f235d577576945183b47321577b1e4fa0cb5cd7cc5fefe0cf6fd8e642037f3b960ba728e0e60c44bdb172d7ede0ff4ed693abc4336a291	\\x69cbb42d60fa5fba79df3b4b4bff3b808136296db9341026f53ee2ca1730d77069d8a691556d91218e659e2e1960a1d0a72e8c945cdd4be303d562bc8bba0efd	\\x2c547e04a3894aa8afb496638e94892a89ed86e843fecbb99af6889f3259f92a78c79e138e8f830896d0f5341d0936c2cd290f26dc03be8cd6a9dd638690ebb35f7355c4483e6d464f20687ff6f9bc5c9283a688489a7871e39249e8d76ee5c84d1febb06065eb0fef15bfa5d1c4ef9f3584b8a2a048cffe90496f0af9962871
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x827e47332bc23de62e14dbd79c46fefc3475fef987f1157a513c3284f0f29fde8154b00d55b7bca1425209bbe079b369903b273c9aa8dbb3f6c96c220f4aa3c7	\\xf8a964788174cd4df7c7e9e0b60ee1cbae18fec060325164cdc05212594ef012	\\x3e67c06c09b7254a2e56fe99b15a9ca10cfdb22c8a73a9bb42c7f4e30f930d5ac32728d24a5e039e1fea8f20d36dfb9b71fd29d6e90f72290589c49cf2585d23
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
\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	payto://x-taler-bank/localhost:8082/9	0	1000000	1578169950000000	1796502751000000
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
1	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x0000000000000002	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1575750750000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x2cd20c6e1d3c03e06e199c1b13643e146973474bb9eeea9508916816bc4c765a69f262dc3444a200a951b04796e87537f98d43005931042f3594d54173b36a95	\\x3002207ec50f8d43f76208a1a5d1bb5457b75297ccb2364e39150bf14a1a38fcd30a7ec3e428366c8fde566119fcb4ae56a241acf1262b3fa4a6407aa1edee17	\\xbcb994b90ec1a660cf06e2bb7bc03528a68f6cccc8aaf370ba51e05fc73aa2c9d815aae38cb92c914220100903611de4c28f8c81f066910bd32dd5a207d62948be221402f2f878d79c2042865a18a45186b62502968ab123224c32d7a6af656ab2bad1d78e6896202ccb1b45a82c56a069e69f043284c4f39e33b23243455530	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\xc301e63e4a44e3e5df3f30f18eff8c31ccc33b37a4407cd813d2a39b3e3e8d774a14b813222308d53eb06d11ad24e2ac4987f5c83394a56c61c555f999910f03	1575750750000000	8	5000000
2	\\x38615e75a86841de0d6fbf83dc5c99a7802a7997af96104165b885422c2f1eea86103abe5fac6d80a6fd3a3988e1e2b972c186f4cf6bc43d2af0bdbf768ebaf2	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\xaa3fab7ee3afa061e093dcb579c606e0f3a75a75d6024172becd5257dffba7e38d01258c0569988f1dc8fb63b48c63def56a00536a26903a06997b79a25a6b016ee6b334430e985155ddb305e99be35486f925d79ed87dc1a58bc46a54e16e1ea1b9de189eb50146ff8da7053d60c40e1bd60e21dee2970d1dab9cfa8ef83a0a	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x896f993b808a473a0fa24b41fdc5f85d2cf7891de453835af060c6b56488481f8a1721bd17eb542b093386887ed25d5b40c0514d88021f9f7a8cc4d4d784d003	1575750750000000	0	11000000
3	\\x066a6292891638784ac5dc05e19e3cca7967724a2e5a8dfa88c2fe78a250774a65bede8549e049d361bc88fe9b5955653778288597427fde373afd8e3fa1fc9a	\\x5ec53e83801df0d0c2fee937186a203d2956f5ffc9703e3bf51688e5d367260c222db4eb7a4895598bee242e7596416efe6bcadb21cca634a42290bb3c2162d1	\\x1f8c521bc5070870e06d01fa01453af939e628407b793e939ae6c004416a67f3c4777254906aaaf2df454b4f54924bebe1ed4da6f3bb369f3f1026dfcde27f13fb89076386664cc77e834a7fce7e2f9bb48d3a4ce787204db598682558df7086310a50ed780e1c683b88f3dba18c0f2b47e640b2c5cef5b360498ecbd8a731df	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\xdae0d3a8847d3b71160e13be0380f46887f1b79275fcc34f8dcaf4e51d825fd90b5db6d3297043b953ecda5af1326b005e23ad62e4c4761678981105a720f303	1575750750000000	1	2000000
4	\\xdfb155a0cbaf5695a09608c12f11691d0f64bca3dfdf94a9f5801d2c76acffd325fb0f8dfb4ff2e62cc7d1a5322dbff7c355669de98ebaddbc38bd3ec663896e	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x01720846d25f6fc17b1e493695ed191a370093dea1afe4f425ae83fc5d5cf3dddfa540993947655bb379fce77c1ae9bcdeacdfcc348e9fb120e6f8c2f40e211a70734004a7b80652ba2e802d3974791184cbc847abf2d52c7b6a8cb6f52fbc9078f9b07a7e25d544c43e3cf701c85f7ad13447ebe4860b07c41e3677df39318b	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\xc1941bbc7a258983a2a749ce8296197157fb490e7559a540b0a15f46e4e0f45dd51cc560c189585f97cf93d23fa1cea445371c3fcadce28237c49ff4b3b31206	1575750750000000	0	11000000
5	\\x92ffa9a6bcedaa124df5cef862b3589d8ac067cfb32ae2348f393d9cb0a5df78fdc341418e82990e9717050e10bf3352d4ff7063da55b822fa4fc10915908bf1	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x5429e4712f683c5e87c870c52c40cb461d678dc9d561d951e97d171907ff80aed6f5d5a91a1eb7111f0f084374664d5e3692d9dfeae4747f344bc733b6ecd4877164b41e2e77e0271411695871573bbae28d80020f4d8cb2b36f6fee9ba4570dcd9bd0aa7dbdb5eae1d4ab72a94b4fc527595ab024ce368402819d8ea5968696	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x8cab93d4a0602a527d3009a79175a82d8271e78eef446e845cbc91effd3db3d3a435a91dae0b6086134eaa4d789998449d97491ef0b3e607e582bbe14c75410a	1575750751000000	0	11000000
6	\\x7835d28f4fb2a7547778bf6f4f3d8c0903f410a9aec5432a59ef079eca405a7daa3770afdfabcbfda9a4f63f01053aed25cb50328e415fc5852f28aef39db03b	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x9c62bb9708d4de9e5f3d0b32fc679bf9f4d48b95c833e64ab426792f3950885a779f39a5a90e0995a3ff42b99752a4fc8b22645e786b1d4ff1f2a1835d1c31db43e8f221c50de9d93fd69602ed00ba10d951754097e106ebef41bd80235a289943859d78485a801fba2e9dc59be6ebb636275c285448c2b4d7cc07b78ffef225	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\xd4de07e1f789ba4df4e81d5935d92ae5cb47e3a6386775b610974b6ab232c1861451e28e3401da7ff3ecb412ee145dafb1386e57f16794a433e35c4b70d66906	1575750751000000	0	11000000
7	\\x28e9df193fb715798ab6535659cdc36a695a02480f218b42c4f98c067c8c4d101ba8e6fadff464ea698eaa0c937f258cc1147aa145be59e1a406eca2ed31becb	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\xb942aac73200ec1d098ebdecbdc80ac843c054843fc3cf2e3375164effc51b6e7db09ce19eaa96fa32e13d8a98b62145a2a7daede259940d593652d321cf0d30776c841de65c4b294f2f29c9feb6c308ef9f09b3faf3573569e49d85fd15de70db596e0987c0ac6a0a1fcb25f2c6e1d96768a9bb19f2d34c65bab7e25f1937d7	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\xf23a94deccc4045bb763f6d09ef73b18238081d5738d34943bcb75f027fda21052e2f91048abacc5b98219179b2cecafeaca8fd45fc76b4d812c0cefe0cdf702	1575750751000000	0	11000000
8	\\xfae6389eab8b9cbf486585e42027bcf7beb9287076cfb3c4d3b78232b500d2d9cbd9945d6ddb857c6561d18df47a70d321f2192f7a17dbf62a8b4869217c7c05	\\xe39ae110abab976bc49071b955865beef61ff5386b44084da8caed4bffc5003596f9aac5210becbff887b99d0059a66cd416c455ff9584bd2ccd60ab9d2e16c9	\\x0d44978071025f8d2817e9107c633fae43d21db05ef13375dba2a202d659e2db100b4ca0dbb129b6d9abba14f57840b06cdbf36beb6e533a26d022845ac3e16807ba840c5e9f77b5c703e35b4fed2edcf96f574b0a02dbc431830ce87ff8e5dd123261d7a55ab23cf8ad96347b686355d4e7afd95603d1dd222eb57918e7804d	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x6f151ac903f7a687c69b1170b93c9cf3b140e4f5676adb947d8820672320b8a238f2ad135094d1c18cece256490f2cc301573256f4eced3f3ca1a49426fa1a0a	1575750751000000	0	2000000
9	\\x95da783c8b6fd2ff94be17db10d27f9e1944acb57025bdc1b1fdb22f5b4296d60a90ab0519dadee1f3205e34ce5740b034aa68f44d76ca0f1b8bf79189cabe61	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x620dfd1e2f2ef8e8ba6cbfbe4f652c34a672a562b010ba6a753c04f4d27a64526d41f1d32c7d4a07af367fb706c084682ad49b562b1176d9d06d994753ae1ca3f6cd5c1025d0e51fad779425e6aa0d005722e71355042093298ce0ea0a8004d5a0b64155b5ca389f8b1ef415f49ef073dfdc46ae87b9a7d10330d6df07b003fc	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x954b42c8d1d1219820f01899f6cc162f9d21dba2bdce48cdec7f9c15ecf837f899b9bc996413fc4f0a907ae33d0b442c36c177b1bbfacf579549b51b5a52ca04	1575750751000000	0	11000000
10	\\xe50771a277989d7e73a0c55f25b61c2b53c6ed0f27c0355364b507fde13b57bc2041bbbbbc5ab539f9e083e2fdd2b47e4d4a12f6d1f33608756bc72206c57cc5	\\xe39ae110abab976bc49071b955865beef61ff5386b44084da8caed4bffc5003596f9aac5210becbff887b99d0059a66cd416c455ff9584bd2ccd60ab9d2e16c9	\\x6d36ea798dd736ae0bade00f8b386153e50c837772adba117a5f52d1f3edfd7babf6b322546de2b9357704d9acc9c3e952a84e89e3888dd6bec882a18b704d617f2291c2ed269ce05deb36353a1ad3f43b117103caaa82fd5249cc3ef3f3b510636ad7bca2bd207fb0f49ade7163e347800eacc1b70d3f66500bc293f6bce293	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x77ce1a6ecf74dab41a320db7a28729856709ba0df89b8b06a22eea6c50281f4e25c2da99964aa41a4e7a0c4e8432fce0e15b9afa0aba9f173a7b11666193b802	1575750751000000	0	2000000
11	\\x9b0b8d37b7d7efdbc7d9ff847836328e28a10d5fdf8246a09cb536d3678bf2065f12c2eb485f4ed6de52857b3cb1082d499227f8b042599d011cfcc0a285be81	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x148fd302c5437c158f96879273315da877e740326d2ca52413d46c802875fbdd135eac37ea40148a48026bf4008f5157523d38170a163dc0ad05c50ce9edbae7c2620792f2b8fdefca1f8f6d028b4e49581799b1d36dc8a17e247ddd9e8d468ca03cb5b6b76fb62cb941afd3b9c4942736a4647b44346b33da9730aff29124f9	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x01421065841844a775f16cb853e791966d150a5b2c6f1aeaeb783899ee8059ede168e41ad0077d66563684a87c31f798e1fcfa55a1c625f037b8885a842d110d	1575750751000000	0	11000000
12	\\xdef9d2ce88a38d704df4a2c269f32d6e42875cb3c4852a28fc6e3bc6f17bb5149bc144ba36bd538f915c9bd92951c2d359723ef4af56f87315fd21d579e64aff	\\xdf3a38178b955f4788fee7b94821ade4de7051dad638b6ff9de8a6df41c8ad64bc76bd8d0b648797842ea69436e59837a0ad2356169802521d2bfbb57f085c4f	\\x5707d56fad94a8150dd98f8a69d0ee0f0cfd87974dd25d718a98321fac7f339abb90cb8cf3bd020b8f9f0156778437dabee767e0961cf29d4325f15b0f9699c4906b9bd7f50f2ec1a5a5986351520a4c87fe765beadc4154bcc07e405675b51e90821f694855c6e8af6c761294f62514a39dd7f4647af430ebdb0155a3c532a0	\\xb2b9360b315eb790a61269ce67a600ded5e4c3b2d04eec2da1e6eddf4c73554e	\\x4fdf7e6ec1420d4502b34109ec7adc053981e317a721686f5bb87828d3b1094afebf5c1b20f550b6ea1554a933432d86900c77eb5e2a9c31c971647c38e3b30c	1575750751000000	0	11000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 10, true);


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

