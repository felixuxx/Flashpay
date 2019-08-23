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
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


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
\\xd1a5aa7e0acc16f790318a166b50f67858aae1ac79a5667167fa82a81f68456396316ba4a9cc66ae477b52b9e602ba9c9f598395ffb8dd5e5a22ab720d0f8e61	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x245ec922389d1511b333460de2c12c23a67a6b5fa97c27c75258684a07aff9545810be2122e5599b6dba5f9d0794c7a9ab664f2f7038277e0992b91186cc871e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1279b7cd8a3f37a4e0a04223f04d647e607532c1f7474136a403c4335949961f47ec0305a033df5f35bfd33522eac54173e2c1635276a91dec127f7218f36cd	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71dc03ef32d3938d7014e983ec9d9bb3df06b34cae85f20f44d0b01ce407200a3d95ca10ae82b7474daf21cea85da3a0b08e355fa96e3a099d4a04aac2ce8bc5	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc924b7d4da80d8900eaa31fb66a7fe23a2fc851ea6cad93886587c0ad32a326259d35dfb90f081b14c01c53e3eaae7ff19bf4dc77dadacca4e110146f2c044a0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b33dd3fbbe50fcbf2227591977603e4d67550c50c8ee6f40a3e52a5b369ce26e5701d71faba51ebb700d65a520e12d5fbbab3f59b1a48311dd0ecacc1517f2d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x985980b978d18ddd82330f22ca3f21eb0f17482b43ca26cb5b8a9946e779d9270a7847a892b894a49845994b679acdf1fc4b9d5cd84f8fd95c8249b785de5fab	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c63994f372703fb043fba2f0c46675f3d3e0e11dd713b0cb48ff28797dc80aa0d442f105f2e4fa221e6946c7059cecb69245f25a9291c52710a9409c5d1b8c4	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdacc03548141696c54a91451eb501f87076610e682d32c5501401998eae7386165c7aac4ae44711aac9b6431b77fb82678b13caa886f1aea22d662aa0c0b408d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13b51288cbfb288a28bc829edfb3dbcc89a15546e5f36f45b78bb23e3bbf453632ac2e211657ca4a86c6f281210620c645d2c114839bb68590f6f198097d0c25	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x778a9677c8f1196bb877be0ef333b8fe37d607fa87a060f400d68805f5fbc81ebf58103d4848f2dfbecafe0fa32fdf8373bd78e4f76f953ad412127f03c0db5a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70e1feb8e9f5169e39594b0fcf5b4a8f39174760f2adb8703f01d3fab997ebf420fe14a2459a8bc34e37b412e321d4debe663be557e8d74c15154f02c44eb0d9	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b34f212049f0076ff5e107f83b24a04b3dbd9c7931788a13a3933d79d621bd4da537d002f3a1b155462c41c084ed60b163dc6a6d96d444d49d47a7e6693e005	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x067b0b03e6a5e659ccca276edaa8121f039275ab34499812f968f9c4509d41854350a97a4cd02ec8f1e06ffd8256a7c9a0372843877958e965b4f91bce1ac92e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf73e6c02b737462b40b27f150cc4a363f53a6b61b0e28591cbdc9a1e93c61d76226e0ea22d9cd4b69eea03d0e763362444de638a391edf32d0f66a71956f940	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe250b595d8d83265a33cc569a229c33a605fc10db798e93dd439fde8b0a5e9b0dd831582cedb880e0518fea118f1bf362cec7e8464e845d647132621f8cf8ff3	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b4088b5754b0c7780b854131f778918b134d35fc883fa7f0eaf871c5c45c67b0bdf1f722f62e76437d62a5599e8f0bf953d5654dcad9da206d2f986c50b29c8	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b21904f99cab7c62b5667a12acdde856bb2d0ec995b664cf55bc8385065127b9850fd387cbd9ce6fa04636805f070ddcbc9e7a86767e0dd2ead55a69d0ec5c7	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4269eafc757ce521a90aa7caf5f05714f1a7d3dbdca14f1bb28c92cf8d890bf83dfc79e6d4532143f0b790f2ae4c0de49e9e6aa9b8a86314383abdc9de372c9	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd024fbcda1cad3f66ea74119bc484bf4e186b3c0a797eeb12ba092e829e90331c97d3ffd6f1c37f54332308c4db6dd90a99548c993bece65e34119c452135bce	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2493a387ae746f5134894fe9c59bf956f4e087304dcce53ab0132e8d1c1e393516b94176ed897ceea744f3f1ccef960bc136e03ec56da9ad9f3ed5675e2b544	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78b1e3eed34233e26212904b93c55cab8522869c57e17fe207e94911905334e00111be9be295d450850b781e33d6b84b9c0c0608bc84b82d56c0e92e00028bfd	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf0c739eb531fd5ea4769eef1ea3f65dcf4cb1dac973d35803d913664cb98618d84fb87a4523cd87589dcbe8d4bb40a5ff8919a41a609487ee6b950abbd8833e1	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c76768db3a7c5865762d08db00ffebdda4e24e1b3a62e8bfc1619aebbcc205525a1ce9fdc7fa330ea6edeee1d35267d40ec85ee8ce027f0bd6767ef2009658c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2c1481e4d9e94140afaf825a60db9bb9a769a945222545bb2c3a55cd14860de8bcc0778b2f54950aa74375d41f7cfba6c3024465fb2770067053a81f2b1c68d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd43607e57c9f015b949f36d800e7c2e6ce53976b44e524ddc23d550ca697fd0701a9da9e0e4c8a8fe31aea43e7e22196f5a3a7bd87804982666e8539130dd8d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ee7bc6e2554be067a3ea4bd7536bda0030762d8f24bdc58c40607de0c2cb30d7bed05c268fdc11aa8554e84f82db373e303be6c15cdecd210672eb462e696cc	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x235eebecbf88d31a8c4c51c42cdf78cd0e6abc2c452c8dae31fb1237873f2d27462ba180c80d43c608920c7dc92f3c1fa63e34731207c6f9f99aefb11122c11f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2188dc16581b54a4d3239d48bd17c2f6d45d57a7a5b006e091bf89e6f05b5a75cfb5765a6814a96d8dafc2725027e97808d9038ef459adb0adc51cf3276ac23b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44b1874fc484a44264d10fc8e7ac401de5182fc4191d2334bf855f4cc728b026206e44b138c359bbf133d9cc909b2f551cbb0b6a86d24610c64acdf8a3a4d7ac	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b6b230eaac398edf0c1048e6d9810183fd57178ea3ffa1d7edb4f10c163305e427dffd08d43e69ae0ffe97cf755aa36066d8c07249d76b31464420a3ea35636	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe12c3f31766455754745b72790e8c017519f9ef3c88714cecf88e6fa9aee5cc841209f9bbe63f6b6e9a5901d49e0453564002c0e3ae5a803cf1643b844560750	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc5c3f69c07c848de27b87a68cb57c9b9ac80b8c4b0dc9002a7bce1b7a6718b3570a04e20b361549399dd2c3be5e2f370c6fca3acafc26b38236811410929b6d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xce8c1d02f08e0e27d703187e49f219b5216518e819db6b88c58df9cd417fcc57f2e634b71c264809f008393b55bec8e838a890480df458a42437ca46c720fda3	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	8	0	0	0	0	0	0	0	0	0
\\x534692e510c82105a1e5c1b91ed4d3db413775a909582d646f5746488244e3903c8c9cd65454bc61e05b8c570d2aaa6c1d05ac2b973b673a57c860846009d7ce	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	8	0	0	0	0	0	0	0	0	0
\\x755faee4618dab2cac263295c6d70a5475f9eba3f201919cbdc1176a5029150d0f36739fd9cbdfa493166a28cfdb3a52af055316d557bf6502dae248f4bf37ad	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	8	0	0	0	0	0	0	0	0	0
\\x466bb687738698f1c3c2663d931b83987788d697b695ed796a75d3c69a1ccbc1f1eb71536427fd10b40880b2ccf2084ef52ff9bd80335e5e81da361ab34cb182	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	8	0	0	0	0	0	0	0	0	0
\\x5ddfdc5559e0c36555058eba3702b67914a3cab5258e172962b9bc5e93d8c7f3c981073fe3486ebe1ec4dd66d95ca6c52e2f89b8bcccb3bfd9cfb63eaf41eb81	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	8	0	0	0	0	0	0	0	0	0
\\xeb18273078abe0495ccd37b801de44ad5cd3276ca30e8397529162472f563f803cd8495fca6f1b4c0b53b203053dc53ac6bc47edb23cf6d3945d6b71cc3d1420	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	8	0	0	0	0	0	0	0	0	0
\\x6b894b72da7f1a4485b325fab24fbd8fe03c2af8262821a77230fab1d4d49d949f802baec1e2d453e504d0a33373a841621fddf427a4c62ceb1b4c54b52fb53a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	8	0	0	0	0	0	0	0	0	0
\\xfff6c4cf1f8a040ca3fdc906ae929b5a41ab8ffac1636b077aecf49f01ab7b9f15a5b7eea54840f2e76116b5c67a30493b2b05fa3bc236c850cdd6b753e71825	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	8	0	0	0	0	0	0	0	0	0
\\xad893c45aecccd931982bfb8b876271cb161c52a09cb888c6d65bcddc3e1ba25cedca076e4e314d619a4fab65393ccb96b0159671c8c9b5bf71f37d8ed23ce31	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	8	0	0	0	0	0	0	0	0	0
\\xf87978d69f654b71c6b0d277a85d5c79d17a9db2c004d71aa23cee036b575d9f359521d6a509d2663a1617569a16b78b297fd97d2f1e88bb5fcd2e48af59437f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	8	0	0	0	0	0	0	0	0	0
\\x76e4fe7c9a7e5c1dab30bfdf249b6c82e2c8e8dcaf48ee14524ca6a033d4fea5f5b4c646a2bf8b84c80dd149f7bf418d96ae125978dd71f3ebc31283faf4c0ea	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	8	0	0	0	0	0	0	0	0	0
\\x28663d11c99c66eee67cb00bd3fba42fa9c2ba1849d4dad55ed787c410a324cb716b66a40de064b7845e9fcdcfb73be0c7d88601ae00cd470360d1a861507e7e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	8	0	0	0	0	0	0	0	0	0
\\x8672f0e2f09f714581c6eeaec72099e510fbcabf5cab0970ce3169d558f167f369a947f34f07f1487e1f87a1ac689c7a300b5e18e1aabb32e5e895c80a04ffe0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	8	0	0	0	0	0	0	0	0	0
\\x2153252e240cc93750d9f09761019628f23340cfe998b192a9ee4450e4e41a91bf4bf806fc8360ecdfec1ad0f7780cd91d97dfc76a466b87ebdc8852faf97b42	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	8	0	0	0	0	0	0	0	0	0
\\xa7511cef4aa7d247535c613d25110868c0c6bedda97a51315b20b6eb23f2c6caa70c60a44ba418473fb0eae19a3e3ce3390a9e794146cd72ac49bf93ebb48c19	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	8	0	0	0	0	0	0	0	0	0
\\x4869aaaac85a0d7085f8928b3af8e259f49e7f4d0149643d72df68492728d54f46ef5e67a942fe5da363e5f526bfcdd4c8e12bb1e8434a6ec2ff7edda13f1fb2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	8	0	0	0	0	0	0	0	0	0
\\x3afd3b4507053a0d1bccfc3ecb125865c0026da6f5f6cf684487ff1978a17e65090124251e0c515afbf3abe00ef049b06074f52c12a14aaab18d991b4b20f9b0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	8	0	0	0	0	0	0	0	0	0
\\xd798865cf8f3c105ca7d3c93f2df0d4eb456758fa8e867cba725c8f45572f6e741d740eb40f4973863769d8e94660b4ee662b1c0a136cc98d418e4b5f5857b4c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	8	0	0	0	0	0	0	0	0	0
\\x6c8031505f739745a8d5601be61b6d484c0ae432bd26d6dbe1c5666d867c3138edfaf95fcfb1831fa0098f881ed341800a8bb5f91d0f230a985e1522be37ee96	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	8	0	0	0	0	0	0	0	0	0
\\x4fd6b0e40a58505b49dbe6061774c8665a194f1f2f15664219234396317874ee0f498b9d4b1c2cb1485aac5ae1ef29b6385fb20eca6ef2b68d05b148df150cee	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	8	0	0	0	0	0	0	0	0	0
\\x4baff1d9b980a9a915d54ab2b5f40f7a34735a8d2ccab87b8052dc4ba400b7c2baf9c8b23bd5f06b37390fb3f8b765f392add517bcde185f3ca9c6e4120fba8a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	8	0	0	0	0	0	0	0	0	0
\\xe0f86ca466078f8bae4a21f773ea3415679d19712a775c94c035a2048c59866f14fe5c2569be1e2f60117d832a1f7906a6c3bbf1bc709e7aa9fa35586a959ee4	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	8	0	0	0	0	0	0	0	0	0
\\x9cb540e843ac1c92845b5083b8dc17311e51410b61234ba35d48faeae47aef81442b1a97c0610382fadee957a6bde364866b6c7f4efbd64e8cd485edaabf1113	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	8	0	0	0	0	0	0	0	0	0
\\x031d78cd1d01aea7000ed3ebb7852828f11de7fba4dc118d8db84ff088cb42572fbfd11e16c20eb72a3b4c437d7317d8af59db4515668186472ae44051c01c29	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	8	0	0	0	0	0	0	0	0	0
\\xf70203c8bd2df6acc4cbec7396d257a7b4ddc3c3703464f41a28fd35b85d57ccb3318a292cd3c7ebb823411b3a3a1c16d77718b24a69f680605047775281186e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	8	0	0	0	0	0	0	0	0	0
\\xb82a1c2340b3210f4fba1842fa9326c26c508f43a101bc06cf8b8631bb1780526ba7ca445136a8fb5b2ac2dbad8ec8d40cc2f7a643b83541e423d4a600debf8a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	8	0	0	0	0	0	0	0	0	0
\\xc2e7135936228fa7fbd904b467d3769d4cf1e732f6e5dc7cfa569d5d4ffa5892d83ad5fba7d4831b703597d4b229de52989d3c501bc5625de3f074b0a4c909fa	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	8	0	0	0	0	0	0	0	0	0
\\x19a2a2a160f9cae32bddec8b11af37bd4101eb76418db5177585a5f0e3509c1565892024d10355e1cd81ab3fe74c3cf074de0b2ba13f542329d3a66cfcef25b6	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	8	0	0	0	0	0	0	0	0	0
\\xab23d8d282b2ed54496a4942cb7da182380e6c44e7862c58c77d266a7153027709bae2588549115443498ff75ce336649336fc5486a87994452ec0a8c5d1b026	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	8	0	0	0	0	0	0	0	0	0
\\xb9883749ea758b9a69be9076e3ae42ea79b814dc2b5372047a9e6d45f47e3425b399974b82e557f53c220c3db1b9113cd61ee2a0195facb4f94c19e41b731428	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	8	0	0	0	0	0	0	0	0	0
\\x253f9358a10f8518e8b537524c22b42564af6169b4b77ff42d260c1ba9db087e0a4d0c029cf0fd5772da4d97c1cf9d20a451e8a833527d2fa98fff09b95704a2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	8	0	0	0	0	0	0	0	0	0
\\x85fafc4a21d85ad4f8dd2afd524afb7fcd128531dff705b6656701df7db78d7dc2046695639f7d935e789d039dcfe8d5d60ebd20ee584991d2785f0d49a73e5a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	8	0	0	0	0	0	0	0	0	0
\\x93f39f2ab409802f619d181b92e53413c5f61bdf60b9dcb02ca3fd5f17d622c8aea0905c1821458f647cc78d2eb1d34c9072a15f8236835339ec8d26b8b99b0c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	8	0	0	0	0	0	0	0	0	0
\\xc223e642af65eb41b10ce4054cf1d2f6191fad01181306045abc54b4996ae8835e39c391b2d495b5cf0fb066ce9c82ca1293efb55d050dd5ea945a1228261813	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d1c1364a6ff73843bbcaa7a00c6654abdafe116972114bb2242abf9613893820c30657e926f6570a9eca42499e6457719433fbc061bf042f3c7755c721be08d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9ccd1995304510a445b9ba053e61df3682d86a3d1664e394eab0bff487f0f38e537d273ad0648b8d29f432b7d7b0abd1f5cacb6319121cca4193d28afe9c3ed2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fc4b84136efd8c982b849dcc56cc35e9d654d08d8ef078c4b38f58d374f02c64521eb628b670258a90b1c86a96029e3a8baed851aad914f0b4daaf2e253ed45	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55a701a34cb7c294779691df3c2dd55201bc47e4ff4f36195f2375e02ac00179d52bbb94e105189e206d0281abc34842f2f7145d02ad14315c7289437643434d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x053f6496e065b65d7254747856de07529d0c4c50d2acc463efde695eef2c17e8935ec1b06f8837368b26a395ef23a43321445c8a5787b5bc4969be769b7a5390	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f5c8976a787c7f1227ec316a177450b14b43b576089e4bf83656268495f35afa8fb61b4077ea565f9ea995952f2e4d31459514a6d20659389a85c2ac0031b6f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x888ec2d51972aa4374198ae4df0ee08480af838bd17bc04913175124a3de594a4b0bbb2f928fb36e0cc2319f167810df73382e4f3600d504890b7d431cd14993	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c066d74e71e84dd7dc6035c91f46ab24c713a1275fa264180d4a6a14d2198b37e8ca59bde0b1e893b0edcfdabe3ad08ed0becc0acf75f152947980c037ab282	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x28808f013033e6230f05459b92949bc0401479e617502a214a814aca9a9ed48ec25a3081e644df69f0fdfd91a23eb39f006a96d607f6ab0387df6ed8055aeb67	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17c6299cbea18624256510a381407ce1c69d91fcfb8c28999cdbedaa61daff6e25a25854efa54906ad38fb41ab125fb2bb339f8f99420279c11cdd9e82e71829	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c23afa4f62c67bc86f1e7d00404548084b85d596969e013a356472ee7568b6b3e5c4099b602201962f3ffa32d87d3faef015ba1df5d1ddc636cd91dd64783df	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2b21d0eafaebc4522adb82fc9ceff22a206c05ced81d68ba6555cf06280d8bc2d93a7f276e7972493f0e230f3d918756184582de76614d890bc4b5d62413923	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x49464e86cc7a9f252582ca5327574ad63a4bbc8de95bdb74d7edd03dd153a917d65c1c3cd7813166662c1a5a09f64098f49ebcb3c67668d4e4e343b28cb63edc	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8078e19c420887d47e34a876b8550d495dc5db97b04d8beaed95bf493c0b664fb75b884971cb79ae4f942e9a237cca034d13adee73bf28487dd107dd46ba35c3	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1150de49d307619daa7dd5567c2925ff9673da0c423b1ff0138d525fafe98511daa67007211620c3c484ade338663658fcf59481f7ba55717e71dd11abd5a866	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x293866d2e01c138298e6de3f3f8054d647b0882e3794fe6a5e70d30496cccd597eab3cfc703aafc11e3e4026736cc311ac35dfa1d2d3c76da38c005a9e334b08	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd22a40a5a3fd9c8fb1f3a54342fe7b7f07f1ad0bace257ab95824398f2e2fee70ebb3d471cbff87a657aecec1b192cf50e07d866becf0071e2d85665e57a9f53	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0f25257bf15d1bed20f4f217fd6a7a3ebe0eca8a1467d1a9934828dc2bc6df9403600bfad07eb261f794a60eeded7e1726a151e29e950989f91b79b3aa1dce2d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x741de2ac75c7f28d0209c6dadf37f9d54d6e39d1b12b834858497511c7f7418eb3943c41ef89a655f40211cf0a87a17becbfc4c18fa2ef923e65f8db2a1ee435	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff5e61e3ce95cf3c60971fbadbec5d911a284236a321412328d2723388364f08ec04030847d73d70a70c40a54c70b153bad44a55b1d45d313353d08c9732bde1	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9eb37641910a9a28fbbd164cb30caef7870751161517a3f00b0366c61854419d853476d6e9e7b39e14e395002fd97b72f992bf0451d649b36f312c46bbabd49	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7230763b620106e29ee3414020816e4bf0b3339db29af8ccba2a0fec4f0d8e57bf9e0e04018d4986a3c69e9918526dc6ce3020075afb8763821bf96957626217	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3e6589b0faa9ad81466ea899492af6fa6ed9242b6dd33bc0427e3c2d96e5e4673b2013d2afe2e0a426d3f653e8fa845e1baf2850cdefc41595bc00d030f25ce	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44b5583b1b6a2bc40393eeccadcc94c3e378b9d37b47ee78bb22edc4c293c7c10ea051182514f4a59173c94bfc0b38b9b10e25b8b97738cd509522cd09d55c67	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x666cf2132806cfce370bee7b940951589a4085d89d5521a562729fed7593205c04ddad29ac77761d6b67ac6a5bde69f12a265d5a52d9458b15857c1b94e5824f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc849870b61b4ce8ff5db32820972d2f668c0c33eedd95de84a7fa7d4d7e9212321726db605e2c986b656b78ac50d49c75f2b82bdbd27aa8dc51d38b62de77a9e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe5b1105a292f1b42a5fe703537c69a3ae3cb6ca5c0bc523ce54b6fe4d8f321ff7a458b6d5633b79a7e63ab68d018172c3ad28b029e335638840dfa65e0f5ee4	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c63d60625a90bf4a0bddf957ddfe2533319614e117a2c90636a8533199c918c6a59c18d243f9e8d8f7d1786ba35aa13ced396f2c5fa7014102a0a2ba5fca911	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfde2ad6f84ccc7f6fbfe6760f26aa47b537a504c5cc73a8f1ad449aead9bd91ab9e4cbc6c7b204a9327259e2feb96d534a7ece4c53430352ba6e491683167456	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x40fc273925678bd05ce6b90f5e3d58efed2b965384165c6ff7d2ec5e488e0960065b6a453e248d0c09c9c9fab5e804cbc90375e002cc9b8d5b0e1ad59c94115e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x797fdec75598080eda270c054d4063f2021db3af6b68e708e0a67b8b61110c6b484d3b0e2646d61a15fa9cc1edb3d644aeedd5ee64b8cd8f03e0fd0d0c6c1e01	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e478a664be4e84559ab06762a756704d9ff2e08513c7ac579f5adef5df345cd559cc17c3031a109220be89418c9239e045ec359aec91d11945a23a2d9809ffd	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9191d0146a87f095aac40df07e7d1001bf44589282ca3995985f75de9a74a0c784b9bc96f0ebc55c07cab753f9fb5047e50a669fbbabf2e5eb8f61e56a1e958c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	4	0	0	0	0	0	0	0	0	0
\\xfec807782459faedac02a42af104ee142ae95f8e4427c6bcb1a6cb84bfbd210cc1af7dbe3be9b5f3d954f9e924f5f47171638bbba1a64849df2864369f8fcf7e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	4	0	0	0	0	0	0	0	0	0
\\x7126b1b9700f08571893d275895e21ff2b12cf8f0ab45ab24a8d3affaaea678af4ffbf429f4f5144d17d7ad6a16bdbef2b545aaff08f70bd3eca4608abbbba6a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	4	0	0	0	0	0	0	0	0	0
\\x921299cc5f2b6bdb69ed4e99c27241f0b174c0390f202865d4a3ce5507c060e706ad0cf344661112e362dd819c283287638b8832bbe088ff208355f44e4c1da4	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	4	0	0	0	0	0	0	0	0	0
\\xb8eb42ae75ee4a79a760fcb1c1d33fbae12d97e2c22da85bc6aee5997cabbb564c9c8b4513c73e963ea33f1ee287f02dfd79a24734144e78befb47c44cf0a66c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	4	0	0	0	0	0	0	0	0	0
\\x4ccde3bf37d81314fa48735ac0482ecc62414e6e1f525f78936fd6e4cde5ba319ba085c94b8a1acc8fe480d38dc056f81116650e7bec0a50307ac31a8a4123b0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	4	0	0	0	0	0	0	0	0	0
\\xf84c5f8ae79a88a97c51ea5fb97e6bb3dd9908497c01ef8a08da2d3d6074b28228aec957df6e41245cf9e81ba13f9ea2402c67b16c8fee3719439d501cabdeaa	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	4	0	0	0	0	0	0	0	0	0
\\xca14363cb447f580dc1bd49b77ccd6297a1312351fd291ebeb1e6ee8a779c6d62248188a27ff3751b8f72d7cb46c17497fa3ad2670058213eed75f29757844b2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	4	0	0	0	0	0	0	0	0	0
\\x875b538c03f305325b50dc68132f9992c671437e60df9b9d71c2441f67a0b647b818bdb27d1598834950b18c16574c12be51df61e7b64f2357a9b12f8783c530	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	4	0	0	0	0	0	0	0	0	0
\\x138972f3e066b21d2f66c999550bb8aa4377b51992ac113ac7dc8939f273cd2fdd4009bfb6b2e4966146c02bebc45e1a6785e927d5862d927fd686eaf3367152	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	4	0	0	0	0	0	0	0	0	0
\\x0c0a4050392078fcc72b287959bce2aa4707b48a90ffd9d4f17f65703db273679c0df08d9c46a90f9f68d9149d500db015291799c9a00c2018b9d3e70511081e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	4	0	0	0	0	0	0	0	0	0
\\x49d4b224f181851c8fab741eb3ce3726fd3465f87f6b9aadd9844df4ab3d7da344dad137ba19ae11fc657dddd8cb507984f3ffe887caac8173af09eda7bb9605	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	4	0	0	0	0	0	0	0	0	0
\\xf1a7f51623c7a74a41b7feb52346737b36986ba4a2a74f65a3dd2f70f509426240865650fe8c651370739489c66dca8e5ad776e4ec3b91d5a0ffcbe8e4ea9e89	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	4	0	0	0	0	0	0	0	0	0
\\xfae23294729216e9e69a5c6384c31c6b14c508c1940ef39d666692bb6098655735f4adb8dd674534d07efa8ac0db0f912bdafdf3f8f7a0863ac835228944504e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	4	0	0	0	0	0	0	0	0	0
\\xd61528e762d9dee787a795b6c480823f2ba8319edb04f3d6ed8c73c2d9ed3a97cfccb353f5d65c1785b0230d5860e50cc3b2600232b649e3749875949f062232	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	4	0	0	0	0	0	0	0	0	0
\\x35764feec9ff18cc8c1b50ba1c9066dfd98d3b5174e73620acaf09ce32968797b1f5bc3cd4c6dbcf8a30908350a6e267f58e6f4d206efa0fc46a6f6df63fc05a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	4	0	0	0	0	0	0	0	0	0
\\x8b2343027a88ecc67ed411d2b0f99c99dc6a5f429c1f2ae4f8e786bed97d461204431340572022e561075d60af722277152fcf808c0117b669db02bb4fdc8b32	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	4	0	0	0	0	0	0	0	0	0
\\xcbce679e67b8e5b7d24764525f2aaa1d88a567d171d30aac82f0e920b0b3b71f03978efb2a8462d6ebe0d892fb9fed3bd4cabae53fb85a239af05d009115c4c8	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	4	0	0	0	0	0	0	0	0	0
\\xc7aa86b8561ad15dc007ce572a6f4f125f80fa0ca5b1a6853c3c8fe835d2ad27da0fa505ff93a93bbd0e7007a5bf1d21d11a026c608be7eee2326086fb8b0de4	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	4	0	0	0	0	0	0	0	0	0
\\xa9d2cdde5024b0f67ad8ffb313c57ecdb8c55fa6a5b662c3067f5e20e990209baef0684f8d5a53c74153a9d8052b8ec514e2c7de4ab45d3fbb87728a5a64ddad	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	4	0	0	0	0	0	0	0	0	0
\\x108f8d2b3607cdeceef87d453d551e3ba8aac255292c060442fd63edbb1c7575bf4fbdf0d2e84728ac4954c5516468039573b073fab73d8044cdd81f6eb375bf	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	4	0	0	0	0	0	0	0	0	0
\\x4eb32f34248fa59bf60c9f84e72a13e13202d598f5b95057aa05fdea9ee1c8e6d7edb6f63275b6bb2c9f1870e379663fbcf688f62a7579de1869b9cb58842cfd	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	4	0	0	0	0	0	0	0	0	0
\\x867d6bf3679ebcab9ef5c1826bc1290d9fc45bbbaa8f81f3342de31a8ded7421fc4d229e5fe030e0b8112610afc656ddcf92176e7606db8156528796caaeea32	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	4	0	0	0	0	0	0	0	0	0
\\x01f319792dd43b5a274fc92f10ed1316965340c808019a03b310874a478c561ce33c7f2b6d5c32215ee75660f9dbaace11a4401b8edc46440d6b0e0afd2e0649	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	4	0	0	0	0	0	0	0	0	0
\\x59c4327dadc5f4d437351697da1ff7f49ccb9d182c536c39a9e8813123e75910a5854544694d81e5f3b18fd919324e8fba5cf922ad435f020842339462ceb5cd	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	4	0	0	0	0	0	0	0	0	0
\\x040863c612e71a1056f46a0ba007142f47aebe68576e1a4851ad73e1653aae8467f99c737c9672954b2b5c0f51a63b41585031dec4036ed8a4dade7499cc0e50	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	4	0	0	0	0	0	0	0	0	0
\\x6c084a92f03055ee407a58d534a8c7bece1213ca032c1303adb92328ffbeaf99f8251b2cd1b7a52111ec2e71c024c2fcfe758ab00f6e4a366d8fff74d90a8b1b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	4	0	0	0	0	0	0	0	0	0
\\xacd9aff6fc7f043b1f53fb7129d3b7b7efe329f5feccc2c980ee9ba48e481a405241a3730671512b3d1487c1047a59bafe9434fdce1aeeb8d37aea663ad8d37b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	4	0	0	0	0	0	0	0	0	0
\\x9843f4cc13e793b0a364300e08d95b29952522bd428fbe26b674efd2205e6ce5f07a862d99151713bdb2776f4d4fd8d9c96be41285abbe462132351861d1d25c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	4	0	0	0	0	0	0	0	0	0
\\xe74e3bd8057fc86c8a31b802ab44f4e18dcc689f489e39948c030b92188faf9ec6d463fa676ef13c3b2a94ac8373fc8d49a794795943ca2bb488739b3a03f882	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	4	0	0	0	0	0	0	0	0	0
\\x82d4ff3f544fb60065f3a6d135520fc979965b2dc574c6d7c84f4d15f2783195372f7840e30fe3a1bb6129c33ef6d109284c44d00a19b689dd3eadeed3aecf93	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	4	0	0	0	0	0	0	0	0	0
\\x9816381706c6b8bcc2507c2f66e3bd2dd6a9eed943c2fe0a2e45dd0188ad514858f2b7dbe0dc4d023b4da5eb2c1b48f6cfc6e9082eb94d864bebd2fa04ef9227	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	4	0	0	0	0	0	0	0	0	0
\\xf0eb7c2c7af6b5d10e50cd84962b084f357dd570ab7dcace08e30e903514dea19313f6dcb0f40cd53d455d5394a51599518f5654e7bae6c571b3b9abcde971f7	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	4	0	0	0	0	0	0	0	0	0
\\x413cb63dc48770bf6699e2d6508672bd2a5953ffc25dc4617948cf5da98c4e615587ef0ab59d3af1377e8e245481e2ffe69d8e84b88f643f372805ced4428b4b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	2	0	0	0	0	0	0	0	0	0
\\x5c9621bc1cd55889e17e5c4f6b73c0b0ac539cbc05473a93fb758794ac2c2a7cfaa25d64206422403c89c465652b723dded1801a314c36ea28463be535d19820	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	2	0	0	0	0	0	0	0	0	0
\\x1612a8e9537beefbecfcd29d312b61fcab2aa14b88f781afaafb6c7e96a24a35098f8b9eada3eb755bfe578c965d88f258ecec396782a27c6fb3ce7fa2cdc285	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	2	0	0	0	0	0	0	0	0	0
\\xde274841ade5174e31b7fe9de1071bb5e14ca14672ac529fbcb94c99ea0ad8bd20a045d7aa0a0d2284fb37fafd1f29a9ef52910c803a68fbc89046aa4d58714f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	2	0	0	0	0	0	0	0	0	0
\\xd6cd4dee3385c172c1a563895781186e8453d7e89a94145ef594f257a67e8611678bfd3281368d9514c87428625b1f13dfa2d19b7fd5524337533e664455e892	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	2	0	0	0	0	0	0	0	0	0
\\xc74788c323fb55d59ad5c4fef18d85a0d7112d89574bea6916fe66b4e1f837e41af5dae05e6629821d2bcb353ec2890b3751018fc472a16fe9db6c266c53c9c5	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	2	0	0	0	0	0	0	0	0	0
\\x97172a85a6110e13adcdf7f5e16bf59ff81a2a7548597e6130f9cea9982dab4853080cc4bcb645152154ce3e8284fd2f2488cfd675faab4c8f220af6b6be19d8	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	2	0	0	0	0	0	0	0	0	0
\\xb93b306d9c89568b704f738a5dbf1bebd3486b6af19098344727d05cd3c12c182735fa889d54dcf691b147eb6682b0297157e795d3304bd8e8b70bb935642605	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	2	0	0	0	0	0	0	0	0	0
\\x02d459d063910395ecab5875ff275122b6297554ce6412459adca0943d51cf088b74d162fefc122928426305afba25e69e26021c6eff7f840840cc6691a04174	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	2	0	0	0	0	0	0	0	0	0
\\x7c3504c78821f9cb1df288e839e5916d6f4fb49221372013256d24059475957825b47ddec93971b639b315c771a47cdba53551fdfcd900b2c884d5ef0bb84aa2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	2	0	0	0	0	0	0	0	0	0
\\x68f372f23ae79a40c9ece6062f889fcec3a66f3755c37c6e8b1a292797e425cb9d40b18622652ff8babb293265c79ba3a36583ee5c447ef474e4cd8c93498f7b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	2	0	0	0	0	0	0	0	0	0
\\x64e77925e76e75c115380bee85624f016d772d582c98a57fae09de725993e45b5fd168fc569c08e97bf94d7f623bba48e9361a36a62a09da6d710e46050a4e18	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	2	0	0	0	0	0	0	0	0	0
\\x2d1fafa363d946c4c2db4eebe87c0150c796ccaa38c7aa6a1adcbbf11314c012c4eb1dd74e50aee64cb9dd81875122debf2854b60ed1b0db52d197e1e86c9a64	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	2	0	0	0	0	0	0	0	0	0
\\xde760b3175c492b42ecd41f25cd434c9db6a3233ce6c5cb35a884aefd1931d2f10df79323a9a10c77dfe4b7d37288262f8db03890dcbcc9f4134c2fadc4c992f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	2	0	0	0	0	0	0	0	0	0
\\xcdbbd3b2fcc7c820d44511fd4b19df4a34737a6c339a1430b73337444f749cf603066a9de08c01a9089418ca30f1560868094be82892f6b91fedd06f3f324a01	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	2	0	0	0	0	0	0	0	0	0
\\xdc98f780456c6c85053467b3a1d3a6f7122299bde3b4605d3e68b9a6f8f8a8f06b8d71ea8127bba60b1d94533c65343148aedbfdcb09bbe601f11da30e2a370c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	2	0	0	0	0	0	0	0	0	0
\\x90502d9aad2c0c5e7c350575448adf8fd8ec1bf723cb3df95691e3bd8da4a97b0857210af4b08f799f916b65b8acd2930cb53a0c2c9e8b84d426fc130a7cf7a9	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	2	0	0	0	0	0	0	0	0	0
\\xe8f16b5b19af6eb79e5c2041ffc2a495634280ba51bae8986e9192714ac21109e05cab61d808969e66e776548d4335b0b6938915864aab0f2e6cf0a671f7393c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	2	0	0	0	0	0	0	0	0	0
\\x6192e182c1dc1e858c9ed8c6f415201bb3d66f63e05cb02e283aea2455e16adcd9a71e4b35badc06eb168b3ee2dab9343d82e0ed54e7409e2ab6cdb17ba24300	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	2	0	0	0	0	0	0	0	0	0
\\x6305f455b23100d1be0b33dcfaaaf49f01d81bb1aaf2b1d8b43e7ade074cfbb8414872ba068be33c4e4bf39c9d792d509c30f289f2a8d6df6e76e01c5d0cf281	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	2	0	0	0	0	0	0	0	0	0
\\x4f76619f3bcbcd052b073923eacf2387df801d644b3cdcca7c8e6d04329ca6171d908d50b6d4e25bd1781f3aac641eb77e40493d4451f7c8f9e8c4d2d414b648	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	2	0	0	0	0	0	0	0	0	0
\\xcc9ea39b0fa0474a77152456f0c4a3a7dab59f6d8c45c2c80da4005e09124c482fc796b6f77752ae3d33c8f75df8e1c361ab5f8d714d4a4f9a8aee48ccf9b793	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	2	0	0	0	0	0	0	0	0	0
\\x7d483cfa57dc450d1e6a3360996127f153efb5cf33e345a0350b7e85cba7d064444be2e6315e80657ca516d72eeb5d3c3d358f5f5e245361bf5e9037309f8227	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	2	0	0	0	0	0	0	0	0	0
\\xf9d6298051d507d00ed117f72ebc6bb011cdf334e4607240bc5bc873ca9c6fbc66a0b6fffe1db6ab067be447844b127ecd280006f2bf45e321f4b746054df198	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	2	0	0	0	0	0	0	0	0	0
\\x14622abfc2df62e7474c53310632fa14ae2d3e73f652eb6650b2e9f1738c5e97496864b9c5e51f06b5cdfb5de4d74e2d4d95599e6cca81956699694d4d7ebeb7	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	2	0	0	0	0	0	0	0	0	0
\\xf8f5854dc948128afa11cf13cab961f4ef456bbe39a0fef0ab149a2dcba13317c062de59c0b7afc37ff56180b67ce5e5ebc199b0137c9b7a09b4b4c73cebf10f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	2	0	0	0	0	0	0	0	0	0
\\x15f18da92b95c578b9105b7f039da775e97e619fcf952ad35797c5e0bfd3d4c2cf674db5fa783db46998173cba45c2796dc5e86357d76ad6e182d1e5d0dd5023	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	2	0	0	0	0	0	0	0	0	0
\\xe8b3a3514045c3213289dde3a48b332a81442c112f78ff4dd842b6a92af4b9a6b5216352a51ebf25dbb00c1bd9e7b2db7b2fdf749bb1e35182fcbdfea4a649a0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	2	0	0	0	0	0	0	0	0	0
\\xa6eef3565c8d0c51dde9de5c585dce8b872d5ee4a2170895baea605ae194d1a329785084e70dc489a5063570a8361968e204d1b28c1f2e738017d6c1f5dcb5c3	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	2	0	0	0	0	0	0	0	0	0
\\x40288bc6050b09458281c4627fc3860ff516b41afecc33831720cb89f7d6e058865404c5d231b56908b46a295bfd3c07e423e711a28762ec9b587d23a5284c6c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	2	0	0	0	0	0	0	0	0	0
\\xb85e6c69c9bbd5b1ef18a5624507c128f3ba580504e2228c31b9fea93e1c44bd60d49353747cc3e7a9ebaf6ea0c934f9e03f2294abd0ea0effea1e887eea1513	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	2	0	0	0	0	0	0	0	0	0
\\xc142580e1acc0367d7236cb3dfbe49a893a57f00fe6d3660b61b91b8f82286aa94b7e6bc675070b8e8e90b1f08d3e99309b8e613c1ecbdf7b4328a9b482a4c73	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	2	0	0	0	0	0	0	0	0	0
\\xea9d19cab62e1b498d2b2b4ea9547d55631346824426d3e75b70fd2e83b2a2939ba6089aaa937b0a710f49c1161a06905c51d28e98febfe8fce3f787a8bd28bb	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	2	0	0	0	0	0	0	0	0	0
\\x95e8b4427a9bba3a6cd38cb33a95d756ac8ac33efa61ceeb2f98a24fd36c4ee4c62cf8fe23896f5e04c3016274e7cafb23fce6af81a4c264d237caeb2bbe0705	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	1	0	0	0	0	0	0	0	0	0
\\x5ee2aa623638e11fde87a6dde4f95344de80db045f131ccfd0dcba4b9f9801c0bdd2cac14d03bebfbaf455e6476f81bb691d5625c6715cd063aab4dbd947f723	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	1	0	0	0	0	0	0	0	0	0
\\x88a64eb6a760d5a2146a660788055e16ed383330687939686dc73a28814d3f5b86ef06f20a3733195973be97abe3d242bdf76fcaa89d6b5dd22f4d38f2637f5e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	1	0	0	0	0	0	0	0	0	0
\\xb049132c9dd11621cfc2d4e5d67fb4d321ac59d48274488857395480b1382a6a8c37b0a2cce1c191424f4f694c53fe5cacaf9fa71127497400b1a9d7de9fe8cc	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	1	0	0	0	0	0	0	0	0	0
\\x32114a06064128709a5c065bc9b76e0b5d4c4707a73e6835daa3c7c44f0e2eb1e46c3b066eb46fc68f947fe4c0b8f103b4dab4909d942c4e23f21a4360f01b0c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	1	0	0	0	0	0	0	0	0	0
\\xf9b63b027def1ac613f3441d6b55a8553a1306bda74830750d4b95440ebd9123cea2a324bfe9f2495c3ad2bd37e199cb1b150bb81c5abeb98c123ca581eff406	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	1	0	0	0	0	0	0	0	0	0
\\xcf6832e5dc1599524723d5b922f76325a7a166c4629f4372210e415151016bfaac62f997968cb24c35957639060157328b67425b2881db4dd25bd58220d9f67f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	1	0	0	0	0	0	0	0	0	0
\\xf20c4ffe93f1bf138010ae810b6b6cb3a9fe8fcdb5a6921151ae1fa6d4ebe4dde656a26fefc22a635ef0a2d5145b3e7e7b4010e8ac1d9802f876248100022863	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	1	0	0	0	0	0	0	0	0	0
\\x09664088f8cda9bbb9bd846792d4d26b0c537775391bb356194a680e878bb9757966a36e0cd5108636ac21ba2f3f626fa18ccb3b3b7f5bc5d42315efa5b98b68	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	1	0	0	0	0	0	0	0	0	0
\\x0df20c45db031e34e3fe136b8a24bdc9b5ff11df44b68b29e3a11d50fe652e5f9bd854498cc0c922e17b31b2064f8da8600e47b021817d475b693b675ece014f	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	1	0	0	0	0	0	0	0	0	0
\\xfcec8cb9674ebf2d0c2cdd428f154b050768dd87c3e9a81ec2561b16418fc195729daac9d46ae963c6dc63e4f6323a8ef46e8067f98c5b31d9b0729e6fa2bf2e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	1	0	0	0	0	0	0	0	0	0
\\xe588b038b86ec11597d75b77152c6ac55a8040f410c5376eafd2646b223f0ede058146b4acf2decd1e3c6931b1646722477d2d8b93e84425c2c5e5ccce5c5880	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	1	0	0	0	0	0	0	0	0	0
\\x7d7e0518bc83605ab4aa63fc1b8bcaef17f75501aeb47541ffe1d612b5041b18b96f51db86b8994952e266e274547b2a0f981c23a8e664bcf9ce06443cd8df0a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	1	0	0	0	0	0	0	0	0	0
\\x64924b9ff58d85b3cd6d58e9577c12d942fc3e79688be9fa02b1ef1acbbcde12aff3da5145ad0ca4295cbadccd92e71be7c39405a73a6599f2804900e1f86679	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	1	0	0	0	0	0	0	0	0	0
\\x8677cbaee533c07597933fedb178b4da1da8c800a3fffd19b8cdb9d5e41197d6975b8e29f2de2e96d8b45e2062bcef5feef5159fa1323018923477c251ca9b32	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	1	0	0	0	0	0	0	0	0	0
\\x605792e2135422e70601c3bfcc10f132c4735c72c0b0dec96c39727aec084ea0829b7622ba91b03f4f251b553fc22378db42b696dde0964476ece8c0cc1255d0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	1	0	0	0	0	0	0	0	0	0
\\x39783edd706c3d43d98458d41ad41223d0ef19db7ac7c3c65e1c98d887fe7b6a9033e0795f1a262c96c21afe4d113591ffdacb5288711fa360bfe51a7af37a11	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	1	0	0	0	0	0	0	0	0	0
\\xfb8c369420250f0dd6ddbc9365048c8a89f51bbbe4f729c609bcccca7189e182632974ea75d903b8764bedd4be6d783edb96cc5ab3ee33efdd15b70c894da51c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	1	0	0	0	0	0	0	0	0	0
\\x56a7c7b7e7514bc7ee44d955d668e3f21faff022756a6a7ae0ffbb0ffb2a103c028368f58b9fc028dc6210e904ce2594725f061a24715eedf4f7610b8159739e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	1	0	0	0	0	0	0	0	0	0
\\xcbb94fbf55f410b25fbaefd87cc5b9bcffacb5fd95f4e98b685636c381177c209e3c0c15fceb8d09af79660d771369ddf1095b2d2fc3bd25fbbf8717c76511c7	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	1	0	0	0	0	0	0	0	0	0
\\xaa4157d2e6509f72d55461d55f212452d80a1561b56e44c9666b06ca1b5d2d43b5160ab95a171e4c8b9f8365c80b1c395a73d9afbe050e50d82c148d4c177868	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	1	0	0	0	0	0	0	0	0	0
\\x0076bd8998b6dfada062ab4d2841ae08588c5a7cb7a2b76d5a6e288e59b5b40f012934e7cf8e6b06da921c33bfddc12d1be73c1b8d3cb6f5b6db067cd97ac914	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	1	0	0	0	0	0	0	0	0	0
\\xbe2d4db6a5d1d06313971f95b5b2b0b3724a3a86aa30f45989075ce29b45bfd63cda1284118b2eb093411d3f00de1fbb2a87687faddffa723992a0000b807ec5	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	1	0	0	0	0	0	0	0	0	0
\\xd0b8eb44a2f2551aab5ae339318a7ff2dd496c13f8c150a6370f19b3dd6e15ea2c7163ce77aa87365fb33d7c43efc72668476fe8353e453cfeeb4eb6f7bec682	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	1	0	0	0	0	0	0	0	0	0
\\x8d7d5b2e3f35fd68828944e464434ea65428b3422fa00ef5a83be831ae8c815e537943314684e30c458145350846321f0fb667f12b299dbe41aa0f81049c8465	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	1	0	0	0	0	0	0	0	0	0
\\xe92d3a61eeb0bb8f6f1e6afbd9b6fbcf1b3fcd83f7172749cfa5ac0ca45d2d793f18cf9f23b5794c32a50419f66b5b9ff8274e9a787e4d1ee98854f10af5fabf	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	1	0	0	0	0	0	0	0	0	0
\\xfc1e30093bc2d8d54776817e55205613af13280e60663ed80286faeadbd3e93b08068d09465ed88ff36ef8e5b964ddba513ec4c106bd2dec66b5a134031ba17e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	1	0	0	0	0	0	0	0	0	0
\\x7e902000bdc11f96d4d1d376fba8eecd8de8cc7c3978b221fce00dd7a6d9c3b74691fe5fe62dad95d6660237c95a3318d77abe18038213da96f31e6924b3c4ba	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	1	0	0	0	0	0	0	0	0	0
\\xd54360a4937b361b0f58b49a2b59821b5b96d8d679f1e51d324216a383d228896d48435f3e34e231d450dcb238107423b0ef142a0bd1fde1bddba1091612f676	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	1	0	0	0	0	0	0	0	0	0
\\x8b62601cd21ad613a65f72df0ce4dd158e02200e673c0d7b46b728a2619e256fd9033ac3cf3cb05776f0869d1281e73b8963d57a2221ca5c219148474dd001e5	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	1	0	0	0	0	0	0	0	0	0
\\xd042a3c136b2afd33ab1674015908aad0cf8eac55dcdb070d72f1ba876ec9b3003a5ddd18e73f0cb696c08c8dc20b4d211386c62009c881b5879630fab30dfc5	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	1	0	0	0	0	0	0	0	0	0
\\xe5d8c41403cf13f94a1738ede70852a0f41fbd10f7f9c5a8fb6169b79be586903f4a6acac84e7cd20ecb28018aaedd888ab0c6656f3776468a09d955755ef1b2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	1	0	0	0	0	0	0	0	0	0
\\xf9b51334d22fb6e74ab0cb44a8221baccd1bf118890378ba5d8724a5e034b93b621e5994f4610f99307865c3536493bdbbc3ae95cfb4fe1c5aa1957d2a001fd7	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	1	0	0	0	0	0	0	0	0	0
\\x969b745fb14dfdbc75b35229925b50fdefc09af6a20680d7af248e876e9215b2df9f859afb7c171245829822984f2fe973f34873b55847a4eff090c441766859	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2dbc767c91cb84229f6a59f8ab9029f0f05fcc76bbe625a6af8674636b362ee55cab9c5932fd83383a0b2d6176a9f636bfeb09cae9ab0a4337e58a857e24fea9	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fe98301152d263ab1550da60fa29ddb5f0b3fa472105d2052d9aa1245d2aa46c45f920ead5a83778f052528c3aeb4544a748e6fb5199a212373f009d61fc34a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5756ce6d0a8e0c15038ddd9022ab586c0f5178b58901b47129384321efe6f11d498a66e0aa6efccd6122f5cedb77b29dda67ce120ab0fd620371108a27038aaa	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x52d36b4ccf03cda558db1098c477a0b365191990a65820ebbaee7b82c75864946195462d545c75b618a16cc6fc995f1683e1d3320272a46354cb4c954fbfc37c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd1844baaf73687f6b8355b093647deb68593a2cdce75dd05c9989d396d7ecf8e94eedd307149e4cff1f5888ecbc947ae8bffcbc659855def4a3e57ac3c37f1b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd112d1fb4eb7c70ce729a071122202224f3e8752550ff6cb26f305b27c182e3dcfe41d82015d5548e1d1c2947453683da3d664b07f40237f5c5af09a4ecfc4b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x69f91bdac976b6b3741634729322c3220b983af3b6cfdb881b7076254dc1be552df2ec5782619e0fc0dc8d3d1599f5542c2ada4f3d9a5614e3d7924cb5e4f5a0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8cf7341d75711e43b96a9e2f6fb0522fab748fc7b4704a6f3787a3935f5cf408e96ce99add394b4e5459353cee1d4c504d35274c72897bcefa0c545858ce1b3d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x43ef2feee3cacdcb0de62531af18a7cf22a45022e33f41924f50a24edfefe5f4e9051101722df695db827b6533d3bc32574aa169cf91dfacd6a8b44a6f2172bb	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe40feb180843aaa1a778c9705f0cccb460c559ba0d4629ad380c9b36d2ac7476dc3f42e099abbdd17e0cf1a1911ce23b5000970024a935018318eec1dbc6df58	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9f56dd059d0ce6c2d00e285add186b59320dcb61fc6ec615758c4cafddbafa3aff07de09545b1f310aae345d809eb1fda2bb78e636694a658ab107dcaf50e87	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x27238ec3d174352f08e4c653180dfa4e0dd737978ec857f02a7c271a88856d58a154c63d122201a882abdea4c37afb2d8706f29b8af015acd38148ba36105986	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f28074ee3f34789225fd013c36c606d11f1ecd5c8f6dd22987cb6492dc2e9bf7606ba028e2023b220b1db1e517e15cdc3245df0dcc5a3a0dc1ed3831bb4c1a1	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xba4e2848ed2a0e42a298c08e02682d3d13aa0e8507092969ba20f927a808b5083e2f4ae180a39e6cd15507a61ab973c5bd74acf44c50f04f8efbc5c6875c82be	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5c8a244f8d4df0c5d01352b2e07f70627d2dc2522480f7fa9a7c5fde300ee5866f859f46134a596c3c77bef5e51ffaf5778f1f0b9742562305d2b4fb700a2b4	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe495888b25f22e5672d2ee1f9f3bd6e978110738663b07545d566ef56010273804ba7e60fef23d9e12d82bf081f905b951a3a63d0f6220d1cee65e982440c61e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe28431615d59e9d52a65d0105d0aa5358bbd0e52c62df6450229ef3a86e2a17462c2bcb8c79eb685527d53c0b57b09eb238ec38bff0207b3b9cae9ec7042bac8	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x30e2eafb07f7215b0502c16652215522315d606b68ff51be87104c0aaad5a721fcc616ebfc7fbce89b668e79007ad0651ca27c899de968cbc518b96159836e74	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b184f10720911e9c7545f7df7e585206db2e4c440e9209802a3e5b3bb4babffa8434ae29d8ae442220f50ccc3e668774c53e77c7fd027e60be1ae5de141d520	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0f26810dce284929e7a65c7aeb8b42223b846d51fffd0b5c649db04879d8e2be85910d94f219d5d89021653d1bf22bfd910257f242591dba4d3d91d0055fbda	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b01d887dad329a95034cd2b070a6ecebd8db3847eacd348358936dc58ad4a8d61412f350601d1f01e7b07af0cc4b9142030761f5fe4489f1b5ef64213f383b3	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf91d9d4e31dd1e8711c5aaa24536f413a6aaced5518647b27b1a77c03ec00a342541dbcf0f7d8d147b744ec70d8372dd52a98395414ea54b2d7f181b4462bb48	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x39015c87a3826396466e31caf52594d5a216fa5f1356c8bc48a6bd77a5bf94e77eac06288d1f603140b796c52b6b4c8f577d17439f9ca7c9aacca1804098b6dc	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdb6e2a625b80085b80af16e50868f6445b128305f19cf534334d8c871835c1c6233ab1a479eeb65e73dd332835394c2e37d57f837a212360ee41c9dbb32ac1ba	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb24232d6788a6c9f245612e6bd0548a9aea120db9821ac00eb6b0d84a38dd9f51dffbc4dbb3a53c7a232c14fab89aa380224406cc6ee0b3e48e8665c251a81c0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7418da4e0424db1285c647dc85b69e5981bd8d3286f3ec82309b2d8ddd27b3b6b4ef9e00c08a8af9ddc9f371d6eaf55f2dc20c224dc68bfa4435a2079d7261eb	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6f4007c7d8ec2b55232ad571320a8d6f3bbbf1ef96918c3ab96368bacc97dfd5d9098d274cf9889bbd33d439c3ae271879a8027fe17eef2dd30e4dfe237df27e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbad5445f984f439196df8a99fb81e054c266bc7bc281163b707f1c038b3c88b405d39c98c679b3d7981495722d63f980ab750a2f15fa6209a7b3e9596ad66d46	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x714b00a66c1051d5618eb7d18324c3751dd516086fd3b45d5505d55a2eb61e14b23fcf868be52ed622df47eb87214bd1421be9a4203ec25d6fe5990db3e69410	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1806efa8e768b094b85f4634e5290120c4d835583c3e7099718a62d0374c53e24430456e22963d676636f8ac5300ddf14a860daaec1aae3e8d1304f95eb406c8	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf02a07d0436d576b49e61d2a58413bb5b6614b6723628e52a6b001b961d611fbf838785ad9a0938e6b2353a90fa39ada520297aec3418c8dc66c2239256c4bed	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d5b75d297ff3beb13bd2281569de0db9487e52b77d2492e57f4289fca0f172c81ab0b62ebee41bbecff5be55929bdba40410451d66f82d14ad90f850981a12e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2362f597de180c88eab380156d82b84893f16301e038b82241da8e8da052a2caa95f77ca3b2572c98424f22b99885475a5c7838e1ef115bfd760b5de82c70c6e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1566559417000000	1567164217000000	1629631417000000	1661167417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x106594dd41ad84e6636e37b612f86b9ac77e8e9e718f886a61367fd9dd384f0656266332fd390c678f603a54bb3f6b13df879038c0e30601b4deb83aa741e2fe	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567163917000000	1567768717000000	1630235917000000	1661771917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x7ed45155b49d14c74fd116bac409a62e4ea31916e08835b486155e2703d055412624d2e2702b40f9790a053a0c4715852d602cd2609492faedd2090ca95bd944	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1567768417000000	1568373217000000	1630840417000000	1662376417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x7c5d5345b9755d7643287805c703f9479465de3d4c25df7ae0dc9fc4a8ad0d3dab18bf6c263fe3940093fd9beb91a4d1007cea7a6f1b1934c9db78d7f948aa8b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568372917000000	1568977717000000	1631444917000000	1662980917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x05b94d66027b505e3c31785656838e66bf911e58d2214ab4d45f30ffa49f180750b80aace41391f18017435c56c88ac0472332a340b2a28f57c56d3507981d75	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1568977417000000	1569582217000000	1632049417000000	1663585417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf0f57aa7dc6b7d5e28276aa67c9c9534001589038a894bf00ac2ca896a8131d8bcd8c1acf5af07a969fd39ca6b395b3da191ae35a14522f6c385c6c1bbe16a6b	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1569581917000000	1570186717000000	1632653917000000	1664189917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x89d969cdbfb42a6c5625a3a55c8655cbf9a257a2189e321492e41b8d89b63f29586061c0b15593c003dc8fff30f265763e29f0fca279dc8844a5fdd36cfe901e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570186417000000	1570791217000000	1633258417000000	1664794417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x9282c622cd4279c0ff624ac8bc2549f22466513e9d9f72c666fca21bd2d6fd04844328aa8e61c0953ba45ffd158d092f693fcc5591dbc38747237c740a0f6019	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1570790917000000	1571395717000000	1633862917000000	1665398917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x01782ad38e7ad3b31afa8db8262e403109ab57d8b7f80a7d7aed6c1a989f4b2b15510f9414edc1260c144c5cadb58861dc07d378666152a42860b4bfaa73a237	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571395417000000	1572000217000000	1634467417000000	1666003417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x14993330cef21a6be4327f5fc514006788a11439e7827748f3369dfbe4cbf2f4fef8209b5a21bd6124c6e43d59a2ca99302e4a2ffecc03b73fdac7a94f6b7b9d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1571999917000000	1572604717000000	1635071917000000	1666607917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xab30d50848314bb357465efd2016a1d437c8ab891a387adfdd752b2508b8b402c5a45f7cfc958399144efa4eb7d6c9cff881e9e1b9bb03c4d12320e50d96e0f4	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1572604417000000	1573209217000000	1635676417000000	1667212417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x10d37e35008f8d6f50bf44a4df81f429fdbd27a6cc0db815fee51619a18fb9daba44c86254efc1e5ead7de2d8ad31853c17e9542f6d4ca2f26dbd524071e6210	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573208917000000	1573813717000000	1636280917000000	1667816917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf3bc03f24a307f469765c9afa59977b1997f35c4162866d4f09546ccf462d5159f81e52471b084a88037fd24a909a58aef86ec1ea5c25ae74f005f00e6e8ef0d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1573813417000000	1574418217000000	1636885417000000	1668421417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x432ebe0cc6e7291f550bdbc1d9e6306588e5897c0ef835dd47f37db2f65a16928da2d5c94a19efeb6b60110891475166a16528793bf9f8b833adb3850fdbbbd9	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1574417917000000	1575022717000000	1637489917000000	1669025917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xa8a36a83a596882e13cb19966f023f4418d2bd9c988cfa90dbade05caa2ea159fe8ac0e137f3d9cf6583819c82ef72fc1704be4eadbd0ba5e0873363bc95eafa	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575022417000000	1575627217000000	1638094417000000	1669630417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x928dd297a3332fe85c62bbad7d27f1ca3ac04b4f4958b4dc7f1024b760c22a6b04d0a8d2f0bcabcdf1604643b6c9e1b2be177566e3e35d89b2da0d1b7b71968c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1575626917000000	1576231717000000	1638698917000000	1670234917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x45067d2d2f3924dfdd2b9d4f3d1d05d4c25d07192365d99c8c1eec6755c93eef777e9fdeccb174e399a1affdb0378a25ece1b8213b0dc3cbb71814906df6aaf5	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576231417000000	1576836217000000	1639303417000000	1670839417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x82d24189747dae52c688a65a2497f45a25b51797eb2a11c833a636c390aa489c16d90dd7f440e17ccf64731e5b40e129a8cd85e77747edc6661c2f3da9b38cfc	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1576835917000000	1577440717000000	1639907917000000	1671443917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xc5be497cb52c4e942b4bbb70af011bc0f397a530b02754c9b076187723d6358823f2c3a50a8040df0cb1df6a98c70bce4ca73ea6c7df82c39d81398ab38158df	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1577440417000000	1578045217000000	1640512417000000	1672048417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0bb76faa139063642765224e2cb6823d08cdec488dfe75d82adea73bd61aa6d589454a4980f638d5b9be6bf840b92282adeff326bdd274fb759a9c6ab488ed10	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578044917000000	1578649717000000	1641116917000000	1672652917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x16ad8dacef43400a22fcf5178f3e99d451d820c789fc9c2931d359e574c2e78f55db64edeac82c512abd90efc2fc7c9cad3f295777325d5a4a09b907bd2f9860	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1578649417000000	1579254217000000	1641721417000000	1673257417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf52ecf005a5c1b4cdd66f898e491f2ac538e156093b5833bbf7dfad6f0dc9f0a534ae95244833cf5422c5255357af695ec734d07c6787ec4394a3bb7cf1334bf	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579253917000000	1579858717000000	1642325917000000	1673861917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xed8e3297d44c709ea8dbf389487b025937f3d9980881d06e93c2aa8b99f1fcece7ecbd8502b4dbfd937d1ab561c85ef44d11aad6e394137b6733ea9380b28624	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1579858417000000	1580463217000000	1642930417000000	1674466417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd266c870846fcb4f02cf20f9d06cf83b658cd0e1b313597b2c3cc430bbc83bf328697a7756ac5c516841a718afed55ac8cb699ae42143b271c1bad1769fc65d2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1580462917000000	1581067717000000	1643534917000000	1675070917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x7a528911c40bc4f8683797d13148c43d67903ac9198dd92b7fb0012bb98e2c03204f858b08af0733bbf1f23d4b04a50023e4b7b312888a8845c6fdc68c78624e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581067417000000	1581672217000000	1644139417000000	1675675417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xde17cc6e862124216cd646dcbc2e201d25f72f59594aa2b7a4448e897f6c682605ae69be6365488124853577d6562009121606732f28f25023c59717b0d167c6	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1581671917000000	1582276717000000	1644743917000000	1676279917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xa406dd144c43ce7a4d500b50b4453be933519f6ac8de254442f0468e51579ccaf7dcdb752402acc1bbac3e4f3fd7e2bb4619e42830cbc6e3c603a47bfb76e4f0	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582276417000000	1582881217000000	1645348417000000	1676884417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x502410147d5e66c8c8767b2ed0217cab31ff27585905e8342eabbf5daa8edc7d82d78430b8e27b0b02703a679df54471fe2438bbcf2d6239562b4f1aa65776f2	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1582880917000000	1583485717000000	1645952917000000	1677488917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xfe99dd596e729f616b46fd2038dd1d7af5306128a4a4cfb46a25ef8187b6a3483c696c4d24f684d00a181d79b83f7e8383838a34767510a83ca5539bec892aae	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1583485417000000	1584090217000000	1646557417000000	1678093417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x04674aa41901eb360417a58910a020b2ccf72b60225cf89b55baf3909f683b7d68dc0dc0e206fefc974d3ed1b67313706f451c1d8b8a0631da1d774f0310936e	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584089917000000	1584694717000000	1647161917000000	1678697917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf343edbb84b6d80bf8aacfaa4722f01761953a301f45daaaa4564d68c5ebc9bdb3912e705015103a1be142cf1af7be40fc38aaab8fd008d46bc33a3410a75e9d	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1584694417000000	1585299217000000	1647766417000000	1679302417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x10f3bd16c1f1b814bd25b5d8cd12dd6c619e6cf07fb70d409b8f414472298a8316c61d3900143c4593a9084185e6e2db673912f2237af832ee4dcff64ae8683c	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585298917000000	1585903717000000	1648370917000000	1679906917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x4a9ae2cc6e4ab4855bc34e7a58fda086aaf984d7ef6aae40bf34897c8250c40844d482b3009e1acaf796c1fa65450cfc2bf84239611dac7386dcdec0dd429155	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	1585903417000000	1586508217000000	1648975417000000	1680511417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
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
\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	http://localhost:8081/
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
\\x466bb687738698f1c3c2663d931b83987788d697b695ed796a75d3c69a1ccbc1f1eb71536427fd10b40880b2ccf2084ef52ff9bd80335e5e81da361ab34cb182	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241443845344541453331413936363842373137343139313833344142463344323945303233323544384231344443454532324642323137353539353330333631364245414346354137374635443841393233303336313645323730433643434338364642364436343345363634303731323842323545373245363344383932453332394136454241354131313939444336463842384238334333413943423241433633393746304434413935354543353644433134423132303945383230343730414136323244424332383230363043424337443733363345334135423444303038394239434237354542333037363545433230453034423542394545364223290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xbcd7f8f88a15ced9df47d49da3121352700ece862c92e546bf864a29b10f8d617823c7b398c092961519da58582d7a0977d6b6580fa2da7de3d697fc5be28702	1568372917000000	1568977717000000	1631444917000000	1662980917000000	8	0	0	0	0	0	0	0	0	0
\\xce8c1d02f08e0e27d703187e49f219b5216518e819db6b88c58df9cd417fcc57f2e634b71c264809f008393b55bec8e838a890480df458a42437ca46c720fda3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304432344639314344333145323435393734363539383634463330373235413234314232384432424544324633344637424444453836394138433944384441373245453545344143344244344135464444383839324539344136444439304639363331304435364143413936433134313834354542433039453444353132323945364632384639374634393533433432463838424641424243353842364644423530433738313730374535414136373045464634344137364541303530453931324341433530443638434335383636384238363236424643353643343445424631373939463437423944413036453637383930463743373841373546434233343323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x17950de07379292bb7eb4ab25f87be016caa67ea9cb5bea35f2a0dcf40d273955c0e5ac24a1c40d9b693a977bbee62f539c80086e77dbf07375b240f7d85b906	1566559417000000	1567164217000000	1629631417000000	1661167417000000	8	0	0	0	0	0	0	0	0	0
\\x755faee4618dab2cac263295c6d70a5475f9eba3f201919cbdc1176a5029150d0f36739fd9cbdfa493166a28cfdb3a52af055316d557bf6502dae248f4bf37ad	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304332433241373243313131333036333632463431303145323043454533453230383331353036373343393131383336394635324143383434423146463732373441464333303539304635394237323046433444443242354432464441433837463531304231333637463435384245343736374232463533453339433143413031304131333931413231393844353631373232423836304436324630394333433834393944394332453838374436463641394335424446393541453343434633414545453930363536443131414339384533453746324134463244334537453132323841333033464133364133324439323345444443433931343930303532433523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x9c73f5166fb8eb02f87306aa9c1118ca089ff63dd0cbfe63d6bd3691c1581f143422f8063612ff7521926bb29a0e460727ee6c7e77fe98927ae09d97f4440b0a	1567768417000000	1568373217000000	1630840417000000	1662376417000000	8	0	0	0	0	0	0	0	0	0
\\x5ddfdc5559e0c36555058eba3702b67914a3cab5258e172962b9bc5e93d8c7f3c981073fe3486ebe1ec4dd66d95ca6c52e2f89b8bcccb3bfd9cfb63eaf41eb81	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304534384335353030313931393943443845453239323530454135443732393238423138344436424441334234434144383839423539373138393233343434413636353539313731393938373041314643453945354637344537383045324337463945453938324345373041423533384636364631314133413839313531453031423145353532443339353634363632413335394635383733373230324143363431314236443144414539374531374437343232463031443637373838323138463532353445343541444531344135464146314332434145323339323345344646314436303832323746433432314637334444343135443136334438323833444223290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xfad529c4239475a49627d3c60da4b3d5e3fe6a53d28f139b3dcb2517da28e73d5859062b67ae1b9967eb7b2ff7c012d2f6c0f483f8f9d6fd74b437f9b977f007	1568977417000000	1569582217000000	1632049417000000	1663585417000000	8	0	0	0	0	0	0	0	0	0
\\x534692e510c82105a1e5c1b91ed4d3db413775a909582d646f5746488244e3903c8c9cd65454bc61e05b8c570d2aaa6c1d05ac2b973b673a57c860846009d7ce	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338393545323245303842314537314244314332433742314336463733433730383233353445373645314232353732444535324436454533424438364346444144413539333938343238413839363536463339423731343441323636354234384230333337343031333345434132414636353337313445304545453031383637314534304536414434454437353446314243463635454239313046463445383736353439434633413341464642453343464136373530383235363441443632364230343145394342333334343139323131443633313645444136363246383238423234423138364242334145383531464644333331453734334434304234463523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xdbc95454f75af052ef81f46f40d0432d2e361c923bfcac8633bbc26e72484ae54e035b5ed71b2125e68f6789fda05426a3719378d7e1bcd0a3f9f9398c76b700	1567163917000000	1567768717000000	1630235917000000	1661771917000000	8	0	0	0	0	0	0	0	0	0
\\x921299cc5f2b6bdb69ed4e99c27241f0b174c0390f202865d4a3ce5507c060e706ad0cf344661112e362dd819c283287638b8832bbe088ff208355f44e4c1da4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304146434341423432323136454242413132433831443137334539393730363532364635373941334630424431393035373541343639383530383332324233363936323345373931323432354144463136423438433335453941333341373234463042393039423030344139304136423543443135374645463633414437353043354530323237443244363336353035453932423235383144414344383130314539453738314444433734314131413344453746393631323437424641364233424133373931413735304543363334443133394631343632384236443941304639433333304146413345413945324533394337373232384645303141424539393323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xd0827ebf78e18f3f7dedb85de2d2b24bdf11ab3e74e8bc1ff86f256790b4a52114ac665567fa5c625412b3bd9c3cf263198caa723b52352106f0424c4f2ba100	1568372917000000	1568977717000000	1631444917000000	1662980917000000	4	0	0	0	0	0	0	0	0	0
\\x9191d0146a87f095aac40df07e7d1001bf44589282ca3995985f75de9a74a0c784b9bc96f0ebc55c07cab753f9fb5047e50a669fbbabf2e5eb8f61e56a1e958c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304135374144464144394342314146303932303732344345314539414245414337313732363935453439443037433033423333374239323135364631453432423033384441343437434444313536464445363236373635453443444335363037434133433745383232434142313034353742423037464335464143344242374433334243383533333043303541413445443933413930364334443932303633433534313330353238333946453146454230453839374231443945453233353335443237374139383335413046443632433135423237423938353746333646333438353243443239323942324645314636373141423233353643383042383846463923290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x2dff691f91490daa3c7d720933074da8d471328f8b4f65223c3eb35d308cfa7dbcdad29e5b4289ac7b9fd5c7e1ad434f0efce00fce7fa8c345b2f457dd07c301	1566559417000000	1567164217000000	1629631417000000	1661167417000000	4	0	0	0	0	0	0	0	0	0
\\x7126b1b9700f08571893d275895e21ff2b12cf8f0ab45ab24a8d3affaaea678af4ffbf429f4f5144d17d7ad6a16bdbef2b545aaff08f70bd3eca4608abbbba6a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330444246443537454137303837353033424645323639374537344238443342313444444639333246363731443933323041343641324237424232374135373131334146313938344235334530304638323642373344374530413444413138463243393738443045313035433838373734304242424542423139393246323133394235314234333233433646374541333044303230363330444142453232313445414431453337343838414430323239434330433439354441373937374331344143334443413735423438463730303435373032444333454532354638353344353946443439363834363443394232363237323734323742423132374236464423290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xcd656e539afe20a923a67ae80141c8856397f1fd4c71f3004d54b058f6277024181e6efb919ae5942e7809c7d811640a2e2a8f1dcd1f0495f596dc8a5d52150d	1567768417000000	1568373217000000	1630840417000000	1662376417000000	4	0	0	0	0	0	0	0	0	0
\\xb8eb42ae75ee4a79a760fcb1c1d33fbae12d97e2c22da85bc6aee5997cabbb564c9c8b4513c73e963ea33f1ee287f02dfd79a24734144e78befb47c44cf0a66c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304145413243393235343934413935413836314532364344323643333738433731413844373938373042463235443637444542354636343539423235304134454234353845383446423139334645453246333030454432453832393841363232333644374433453443344138443642393733323645343545433444373030314237364139434641423337333136323543323944393234433534453645463331413143333042453036444439324637303042453639373045303134323941353233374130313036353833343135444446433535423439434441323438453544333932414142423635434542423933363332304333394542393931373442423035393323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x0968a9d16bcf97280f20dbeac9e2fade20e01f3c303c4b90b2ccc0450c12e6f558754b1c30c2499e980b80bc9eb7517a8804aec795660e18c08b0c0113f7960f	1568977417000000	1569582217000000	1632049417000000	1663585417000000	4	0	0	0	0	0	0	0	0	0
\\xfec807782459faedac02a42af104ee142ae95f8e4427c6bcb1a6cb84bfbd210cc1af7dbe3be9b5f3d954f9e924f5f47171638bbba1a64849df2864369f8fcf7e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243314245423334434242313235434344444542423438434143444332344541373932303732413339434544333236423432443933324343443538433843374145343934363831323936443738303634303833333732313631433035363243413533453145394646343339464445433031383646433142394541414142423434413532323443344645424633444641323530443236354436443736424646453938394542443741303930433933413439383338394443443836453230443438444444413932353137424641434339353234444332433441343031363445443439444231433637444133354546314332394643463938323133323445373046394223290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xd8eb0c70f0dd65f183b643c8677eb3044df6a67565fec86990ad202b7b030d4b5b91cd40ea3cbd7ffa1f806d32fdf3f33d83c946e7546dcee7d629266f9a7a01	1567163917000000	1567768717000000	1630235917000000	1661771917000000	4	0	0	0	0	0	0	0	0	0
\\x71dc03ef32d3938d7014e983ec9d9bb3df06b34cae85f20f44d0b01ce407200a3d95ca10ae82b7474daf21cea85da3a0b08e355fa96e3a099d4a04aac2ce8bc5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304337373231384537383632314641303132344539353136423036343736463941324637393433333238433141384634313337313437303146384332433430343738334132343742393430303442364241323631303943374439353130433832393045364437353341354338353933434634304432423036433030454242463237454146324331433232443634423538373138343035364642313938353642423133333845344531453135334443424443443945343238344133354142444538454338454331453144454431444444383744454543363439423338433632413235364433314132453834364430333038354331434437434131394431343746313523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x5c854a5c9483996d5b79c9407fe56f7d01d7e201c4d11ddcbe736752626644be7bc0223bbdd9906c7ff52fc48f07303553e7c1ae3d84e1746ddf43bf61d9a90d	1568372917000000	1568977717000000	1631444917000000	1662980917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1a5aa7e0acc16f790318a166b50f67858aae1ac79a5667167fa82a81f68456396316ba4a9cc66ae477b52b9e602ba9c9f598395ffb8dd5e5a22ab720d0f8e61	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303938393346443139424431433446433844363439413231423835313945313443373737413830413638313146353345464137324230393237453236434644444238423146333031344632363735463634453435393534324539343642333443393143373835463933334537383031343245434142443939463246383430384632303538413645423635463233384237423133343836314633344331443034303436373945353839344237414238423135463445353136303232454544463538333132323143343335384533333237463131314638344635423139364542413731333142324243323633434531453145414143433837343731463032314238413323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xfc3e531fddb8a48ff59aadcebd1d29269e39747eff29bf9df3f0a366a007091b9475ada783f1da52a1de00df789f219f534ff4bcab901813e3e8cee187fe3309	1566559417000000	1567164217000000	1629631417000000	1661167417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1279b7cd8a3f37a4e0a04223f04d647e607532c1f7474136a403c4335949961f47ec0305a033df5f35bfd33522eac54173e2c1635276a91dec127f7218f36cd	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338323839323235313246323539434331333543324532323737413935373137334433394145394246323642394634424435453444364241443541434536463446424243303937373146324346314239423346303132364135374641444539354539353542464545393230444439464238414646383833424242313037313039424645364533423132363931454333413545423941393739353832344546413844323238333744463639304136453743304234333345343946463032353441433533304334434344323439444533413931463345423341333032453245364335364135323132363831313638453635304632363031334442454232373345333523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x9d06d4982c5c2c11f6b52a10d1c092da861794ed6f8afcd84e61fa9a6095a18c19944298fe7b6f5070cccc6a2015b06b1bf13b32ef864e72ce46f6bac08a3e03	1567768417000000	1568373217000000	1630840417000000	1662376417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc924b7d4da80d8900eaa31fb66a7fe23a2fc851ea6cad93886587c0ad32a326259d35dfb90f081b14c01c53e3eaae7ff19bf4dc77dadacca4e110146f2c044a0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334383337424143413330433637393641313236424145354535363339323336463445314245303738423035383736334234313844444333424345353632383743363230433533463331413543454230304238433330323845333434303332394138453943393836323145324234353341444333423244423944464434333445454542444542444243323141393545363632453235433532353441413636363446443041433433323531333042373237383146453330344345413033313630374132443536423743414231373145424245343846304336433935433231393834443746323230433945324239373838373839384633443937333434344433443323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x80475b3ccefe6556cd8023caa591b39cde3c4fca00534574f39661b68bc79a3626a0803f5bad80c2d2c74205f33ff105ac9a634926fc25931a6b95033bcd8c04	1568977417000000	1569582217000000	1632049417000000	1663585417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x245ec922389d1511b333460de2c12c23a67a6b5fa97c27c75258684a07aff9545810be2122e5599b6dba5f9d0794c7a9ab664f2f7038277e0992b91186cc871e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304337463333313836444330304543314241444438443443393444444341313634443543313237433438344331304243443942433534313142384338314237353232333142444135374346394342313146374245324236333843423243383543443446334143363944344444373941414233413244453446453341424142303530434331383843433235324538453743414232383234354434334433393133453142364144413934363141384333393845423130333333423344363130453341453046384437314539334242463533334538443535383844393639433441313345414637394437453033363937463531334432463145303239374637334542384223290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xc771794a67cc691da3220bb5661dae4e63899b0e092b2e950e25b8feb73a884c992916df86e9c39f861006a8a13091ad000038372665c2f0480b8f90fd32ad04	1567163917000000	1567768717000000	1630235917000000	1661771917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c5d5345b9755d7643287805c703f9479465de3d4c25df7ae0dc9fc4a8ad0d3dab18bf6c263fe3940093fd9beb91a4d1007cea7a6f1b1934c9db78d7f948aa8b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304443323434363931413932313241314346443538343143463533463643373939313630323236414437383533434435423636314238364338353039443335394635303241374442393739353746383734334435344141344246374633363232453236434141343932413344353735343244314436423336433445413441464533374532464346434346303543364344393731334245314641454446444233443441434346463533333832413831413236424435363542383632363041303736423331414537453445313444343139393644463742314539413045334246333046413742313842313036303534454643343331344437313138363746323233463523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xad98fdba3c1c0b6bf443338322b1b42a7611e4482ba456630edb15caa8acee988df40c7f02d982b94a81cbec2506bac6bf89534d489db944a55f7f1dc28c8505	1568372917000000	1568977717000000	1631444917000000	1662980917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x2362f597de180c88eab380156d82b84893f16301e038b82241da8e8da052a2caa95f77ca3b2572c98424f22b99885475a5c7838e1ef115bfd760b5de82c70c6e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304444413135343739463243394642313237333938373032393238313941394130353844344245384136444130303346373639323537363337393434323639393732313943364444344336424533443030444334343335394335343941363231443136453535413644393733423842433935354142433731383643353837373934344344364246373046324131313537394333424339423135334230344336434135443744423836414344364332363739314535353144423239323635393631393130423132464232454638364441343336343343394531433345364230434433373830313030363537464439333443323936443230363736373337413141373123290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x2603986870f950233b5cf03dde728f66b299469975e4712fa8563db3e141a7ec8916b31e9d98593c5b03118b5921241623b68e063d8e00ee394a71d56ab00d04	1566559417000000	1567164217000000	1629631417000000	1661167417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x7ed45155b49d14c74fd116bac409a62e4ea31916e08835b486155e2703d055412624d2e2702b40f9790a053a0c4715852d602cd2609492faedd2090ca95bd944	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304445383646393833304643343142363442434134453735433935433034303938423837444633464341374144303243414544343031453746353042323033444535464332303335444135354334443032334443463833323043463133333744434345313137433642423336304636454331314130354533354439313638374434453444353232454346434136434432303543303041393337383038364335453538373943424536443937323541313845373032414237393736323045333434373041423639414131343330354132453031323644443936373838463034464542393133334432424136314436323138384132334636333730313639324431334423290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x2860acdcf1c7051e4b793f6d2f96084b94bdcbcda30ccbcc94413be469a0fae15689677ba4b428e410b129b6565fb8f651dd37811ad742dc7729a9bca149c401	1567768417000000	1568373217000000	1630840417000000	1662376417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x05b94d66027b505e3c31785656838e66bf911e58d2214ab4d45f30ffa49f180750b80aace41391f18017435c56c88ac0472332a340b2a28f57c56d3507981d75	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303939313539393944394331383741323636384231364534413232383035384243373346353638413642413742393737423944424143464136424143313936304143353442363136323443414344353737374435434530443931313834343643383531463037413736433936463735314238453939454133423330363434354234383333424136303235303432423143323733413832323533463341444238393435393646323237374234453934303245374644464336343636324343343542423533434532463945364634444546394335303737464132443433393430354134454644324142453639454439394441333245353134343931453135303341313923290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x3698a0600dbf97045539f33f137bc7471cfd95c80026b541edac5e578c4eafbee9f5c0f261df41b1d2d47b7f59bae92e2d79b8a0482b29da2da536b10aaf2907	1568977417000000	1569582217000000	1632049417000000	1663585417000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x106594dd41ad84e6636e37b612f86b9ac77e8e9e718f886a61367fd9dd384f0656266332fd390c678f603a54bb3f6b13df879038c0e30601b4deb83aa741e2fe	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304637343531453636363334354136393930444144324230353632363030424442344233424231313332413235304246434631334537464544353342384232413034423344433342433830363332424233313333434543383731463330343033423131353346344138313345354242424330343742413235384539333238394334363044443637363838433938344343314231464538323837463739434343454444394631383934363132464645343932384445374644344431383234304539343533344631424342363245463043323331323036433334334430364634414334333046334334344137323834423435393133383332333442363930443733303523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x1b7f814306f58eb9c83b6d21a182bc4bacfd22be9fbcc02274e3378b07ee2fd4a0148aaba00f81faf7a6a2dc9569c346e309f320d11ea4c405149e36b2fc0f00	1567163917000000	1567768717000000	1630235917000000	1661771917000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x9fc4b84136efd8c982b849dcc56cc35e9d654d08d8ef078c4b38f58d374f02c64521eb628b670258a90b1c86a96029e3a8baed851aad914f0b4daaf2e253ed45	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237304643343737334432333143313541424137453937364433323631303841383737303339373537373643453044373643333242394233443331363530353039444135354431303445453444373743393134463842344138433042394531433944313439343931463438343531334642303632413334443935433635354238313034374343453130464345433238423033304232313335464638354241323335464141353132323743463545424233414636393638413646324237373845373239424631313044453246373036443042464337393933444237444343353531343441433632303542323039304334414336314131433639433839443738434623290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x84c1047821206204059f20cec45d2c0f35bcc3797f52be2dcaf3b01d3e07fc1b64961acc032a99116a00f68d8b69aa3be9901b55e3c6894d6edb8d84cfafbb0d	1568372917000000	1568977717000000	1631444917000000	1662980917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc223e642af65eb41b10ce4054cf1d2f6191fad01181306045abc54b4996ae8835e39c391b2d495b5cf0fb066ce9c82ca1293efb55d050dd5ea945a1228261813	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304132414544363239314242413135314143443235384331334435304232303645373242353442394144383331463442414642464139423430424243423836333144413746314336384538313535353531453135353243463332393037344637454243433534453531303531433945454338353738423342443044454143443845444444363235383042334134393544394141413539314139434135453632413841433038314131344635383039373844313130383845423033463442314142364645313439343943304542433636443344464135384434464444443332444636423438464232464630374444443230343638333544464144384441414246434223290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x23d524118fbb82bcbd1455e7b370030cfd8023be968e48b770b73a8a8d7f11d2efa1606487939acecb544410fd7ba726294d70650d96ee8e01c33eed6d925a0f	1566559417000000	1567164217000000	1629631417000000	1661167417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9ccd1995304510a445b9ba053e61df3682d86a3d1664e394eab0bff487f0f38e537d273ad0648b8d29f432b7d7b0abd1f5cacb6319121cca4193d28afe9c3ed2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304146353638303044303432364130333633454646464532353036304443334645414145413642323346444335394535423645464132333732353238423236413534423943354234464431363438383743453446313931434230463635303930393046453146393635324437343543384145433838464246303237433732433136423443353444323945453936353437414334314539383931363137334331463934453530413242424338463543353542383135324132344545393734424346384344453143413341334433343733373543373343384633463543384646303933423734374538373842443842393844363234424246313244333242334145444223290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x14806c7f388a2d665dd3d18d7d95a0733fda89fd7281dd2b26789269aef627337e1b5bca543979107efac5846b2ebee5d8435b5aed8a2bb2d0f02b4d8e873201	1567768417000000	1568373217000000	1630840417000000	1662376417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55a701a34cb7c294779691df3c2dd55201bc47e4ff4f36195f2375e02ac00179d52bbb94e105189e206d0281abc34842f2f7145d02ad14315c7289437643434d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431343638433843343545303139303343374535303538313739303835353234444235364536414137323042344544324236324342434545384331314331463446313338383138453736423033424137354145443542323741384532354336333146424546423131433932423445384644364546443635363442433842443635374233423530384643424142313334433539444442373339364146304141383533384345333331324245413337413839313337363643324235444641363437393733363137323136333634333833324244304138323037454137333446303134363541313934324639323137413543464134424443313932444342363235354423290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xa3f4f0dd00ef896528dc11cf42258f84636189f2cbc92d542e4e792f76a91cfa144d50131a990984b6ab970bc0612b31fcdef7263b4900a0bc146b50ea13f50b	1568977417000000	1569582217000000	1632049417000000	1663585417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d1c1364a6ff73843bbcaa7a00c6654abdafe116972114bb2242abf9613893820c30657e926f6570a9eca42499e6457719433fbc061bf042f3c7755c721be08d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436304139374530364443383743434232443443383235353537334344443143333635354235463539374546333639313944433539354334463631364130443633343932334238394544343534374232393336463246444636394244373935434432413033344539344545333731413942334638464342413446373131463941363834363742343237333934353539423037344137423641353935413044383632323337314338384436443437443242423835313938453237453042354530433242443244454536343044393930414342363441344632364245394446303042383436333736303334353144353931344435463742304145374332344242423323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x5535687b1b5709c8e2d07b289113e8fa87f0443831415974d9d5c8c7281d465258206613a8a29a2e67509a985fb70bf7def05f62f7cf9bfa4d1447f887f3960b	1567163917000000	1567768717000000	1630235917000000	1661771917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde274841ade5174e31b7fe9de1071bb5e14ca14672ac529fbcb94c99ea0ad8bd20a045d7aa0a0d2284fb37fafd1f29a9ef52910c803a68fbc89046aa4d58714f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430324439323330353237304137463944393644374337313135324645364537433532373143453446333145323233343543363746353046434231414137343243453242333737303839333042333232413130323831453739454644454641433644434342464242433339314637433430423546363445433337323137383936463944354334394235363446373133413643364541343244314144423839463242464143453630334132454542363638443443383938314242363136464439443535314636354645393737344345384245353742413835423932413939413032354238434141453135393937413330423145354538313231434530444533384623290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xda0a2c1baada4dd02b67d4dfc322bbed8c94b360a44bd75c465662d99cd43e4d40060d3e9f612d1aa933344feafe65dedb0787762cf91cd5ce2a2d4b449a3707	1568372917000000	1568977717000000	1631444917000000	1662980917000000	2	0	0	0	0	0	0	0	0	0
\\x413cb63dc48770bf6699e2d6508672bd2a5953ffc25dc4617948cf5da98c4e615587ef0ab59d3af1377e8e245481e2ffe69d8e84b88f643f372805ced4428b4b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243333839323539463931424345354630453831423033384346393546464234394139313446463946453938343044463741324244373335454135334436393842394241434546454344443435413930413444343345464437353937394137413832383330313444393942444543463330363135353346384235394445334431343639463934364638423532304133414144383038453143433632414643383338393041333232433231463745414141443736443145374133463934443234434646423342344632334644304143303244363233453132313846353939454139334131423130364434344439314533323638413839413134443632343444304423290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xc88a855e46dd0d8dba5231bd90daa7a931826750563161d0d6434761da0307962979783df71023a2787c91ba65764adb18571ae2bc20460ad8ccc538c0e23002	1566559417000000	1567164217000000	1629631417000000	1661167417000000	2	0	0	0	0	0	0	0	0	0
\\x1612a8e9537beefbecfcd29d312b61fcab2aa14b88f781afaafb6c7e96a24a35098f8b9eada3eb755bfe578c965d88f258ecec396782a27c6fb3ce7fa2cdc285	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434333534453935393135304636333733413541303532303245304545434339363944423734454636443833454234313434393239433541383730393145353336354338333244433044443836454246363637363439313632353145374538453738384133364444353638353632374536353743443132364543454644363046384444373042463446414244373834393935453335453542444539453331343232463341434242463946333134414241363841344646383838453742323935384339363241373936343645464542314136334446364643323743373643374330303036433144303041393836383532333636384345384142314639373034384423290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x4cf10e87ee420955910b1d3b240ab17e9ec7dcf11ceb190bf5f6e6c18c4eaf86ea651af4df582a46039b18e74d304d1c18438b9e27f5b239eefa5a54532deb0c	1567768417000000	1568373217000000	1630840417000000	1662376417000000	2	0	0	0	0	0	0	0	0	0
\\xd6cd4dee3385c172c1a563895781186e8453d7e89a94145ef594f257a67e8611678bfd3281368d9514c87428625b1f13dfa2d19b7fd5524337533e664455e892	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304444374339453733364643334341463938334146363932443831443642324438413936444333343435313042374646413435303543384233433941303739334436384436343638343037393941354545333835443836333743333531343343373633423242464337343737413835464637384546464630353631374645354542413746304134394438324539454437423445373146463741453141394536443234344541303743323536353943373834444437443631464542423033314236323236333431453732333634323043434538443436363241373736383345344333354246324335313244463930314235363934303931393038373838414343433523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x36b3d856996cb3cfaa25d547db48c05423560d7c4915c620568c81b4e6f8bdfbbb817e7788c642c85f70b7800107fa5d308daf188f117e825c0fdc13638f900a	1568977417000000	1569582217000000	1632049417000000	1663585417000000	2	0	0	0	0	0	0	0	0	0
\\x5c9621bc1cd55889e17e5c4f6b73c0b0ac539cbc05473a93fb758794ac2c2a7cfaa25d64206422403c89c465652b723dded1801a314c36ea28463be535d19820	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303932324345344235343042373044454639313145423936373133333941434330373943373032464139313546384231314146444430454443433835464630353138353035304446454331314141343744393335453434363035373832394144393130323739313237434641364638423436314133333239464634453836383931423736303630353138333033344337323742353246354539383930304546324546394442384342393244363631374238393134464235453936303830353144344142304137343137353536304335453641323541393542333435354644454442333335323646333234423742373136453843333733343941384433434433423523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xf99220f2c00321df4bc0d5bcf07088e6e319a382755ef4af292fe1acfe01a7a077a20ed3d1e95f2b699a86c5000c23aaf7f54f9201c758fb80877c69f457d102	1567163917000000	1567768717000000	1630235917000000	1661771917000000	2	0	0	0	0	0	0	0	0	0
\\xb049132c9dd11621cfc2d4e5d67fb4d321ac59d48274488857395480b1382a6a8c37b0a2cce1c191424f4f694c53fe5cacaf9fa71127497400b1a9d7de9fe8cc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304442363744413139303933463643373533454242303138453334413630423546304644443339304538303634414446433930414246333332394544383433374242384431443532343644413830454131313845433044443137304136383742333334433932353833394142374235394242364130383635333130333646324642334639393245463044373633414536453942413538303637353330453630324535383535454436353433323344363834433631323142364542443138373443464239454331384430304346354432443633313743433633393843433645334243383131383536323836423842334439454442374543313331364546333444313323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x894a7931a902c2a9974ffd88bdd38f46ee6746ed964d901e8e4933c436ccb01293ccc0f6bf41e8a73d411b8fe38c9884d23348dda6a91da4991deebbb7411d02	1568372917000000	1568977717000000	1631444917000000	1662980917000000	1	0	0	0	0	0	0	0	0	0
\\x95e8b4427a9bba3a6cd38cb33a95d756ac8ac33efa61ceeb2f98a24fd36c4ee4c62cf8fe23896f5e04c3016274e7cafb23fce6af81a4c264d237caeb2bbe0705	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436363530333830374333373434413545413134433345423743394445373430433843343533414436384243314231314244303242453744453336303133304441343342374441463535313044313946363631303536334436373042384235424637413243433637373143343239454635383430323237313038393231353030413338303036343539444239433832333633463637323844453441343536394139383732303135454139313446324334323846383430454646464433373845373736373236323032314645423434303234323532424536313841303534313631364630373343443133433945363542344636313936394232313842334339353723290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x6b8c219dcfcc21dc1b0437705c47cb3754899fcaef8d9298dc46955755676bb1f599bff9f55fefb4c592e7dee397263eb714c6e12556b6c592e9c8e88c621900	1566559417000000	1567164217000000	1629631417000000	1661167417000000	1	0	0	0	0	0	0	0	0	0
\\x88a64eb6a760d5a2146a660788055e16ed383330687939686dc73a28814d3f5b86ef06f20a3733195973be97abe3d242bdf76fcaa89d6b5dd22f4d38f2637f5e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303937323644444233304237303341354136423030364233344243414343323945333133444332363836323837463943454444383030354633344246463645453644323546323442353739383938374544353634424139444530423231383742434644323938343146393333423139454533304341363846323332323932393830353644313935313645423839443142353446333643444541304234364331324333363537393745323142363841383738333038393436454238304245413730344637374339414334433542434132454637303837463535334544433735384546423144393744324636323535373734353033443339354642313534424641363123290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xcccef5cce9b3463725b56c5a14a313c1eba65046af3b54db66d06232c750115aa62dc49a06d988b85a4b3e5c8a0eeb19999e8264061e5a71dedff25417fab30b	1567768417000000	1568373217000000	1630840417000000	1662376417000000	1	0	0	0	0	0	0	0	0	0
\\x32114a06064128709a5c065bc9b76e0b5d4c4707a73e6835daa3c7c44f0e2eb1e46c3b066eb46fc68f947fe4c0b8f103b4dab4909d942c4e23f21a4360f01b0c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434453441343039323937433834363531344533413344313336443633304235324142323236414639314535344534323238394242393937443244443339303445443636313042463443344132374636374138313031334446373937443843413246324542314238344144423137314133413442373338424638443730353839304341394145444241463241463039413344343042443942394145454137383733424437393332444134313235343044443137413835393533353232343338463635304332433445443444363045464430334343344146414432313041434531363233463343354537424136453538373641394243304542334333373234324623290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x9f16a696da2b184dfce8ef767fbce9da3f431e2322686aa3790b51f86e658c9a19589d90ef2dd45d2c0087d76dc760f5d92fc661edcb68837eb6c372c5d50e07	1568977417000000	1569582217000000	1632049417000000	1663585417000000	1	0	0	0	0	0	0	0	0	0
\\x5ee2aa623638e11fde87a6dde4f95344de80db045f131ccfd0dcba4b9f9801c0bdd2cac14d03bebfbaf455e6476f81bb691d5625c6715cd063aab4dbd947f723	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304131414144344637353830374246434243433230414542333946334430353439433331344233334537444539443441313831303033433242413143313032383037323741463232343944393832313345444646443639393045454545434636433736463546463639323036303238323237334345393431463043373544364333393836454137323436453336463845454433373333433142463343423435413839423131353844354435393736343441324436453446334533354238314645354437413632333634373732303243453836333539373639463733333232383145363236313345374537443832453533433035363033354630463544454531433723290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xc5d9e6464198c1ddebf18b3c55663098bb9299d134094a8e9068b6fdbad4df556509ce78efd4dcc920e7df5fbbb73aa72e607ed32c3947d9266098ebd245e101	1567163917000000	1567768717000000	1630235917000000	1661771917000000	1	0	0	0	0	0	0	0	0	0
\\x5756ce6d0a8e0c15038ddd9022ab586c0f5178b58901b47129384321efe6f11d498a66e0aa6efccd6122f5cedb77b29dda67ce120ab0fd620371108a27038aaa	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345364543424444333843413743423235394233413834413043393735394341323732344146313139313139313536354444463146354238363232423638464236394445433344334245313835394435343330314531384438333742363737373930454337464142323432333334454541353842433735444344353832363838303530363635373244333543344339424142383136304335353042353632363433413032454332363833394644353330394234323641304436374243304235393941313030383631463839383845464631463934453243353938384446434539424643444336433034373044353637334446304642394345464145313935393323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x6e1c51c87403f60e0e3bc1ed26cba838e0cc4eb0844d07059d35e6b122cca1180b851653bb28043144e7f9848faf468a66ca3d0e9f8fa8a322b876a3f0de3300	1568372917000000	1568977717000000	1631444917000000	1662980917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x969b745fb14dfdbc75b35229925b50fdefc09af6a20680d7af248e876e9215b2df9f859afb7c171245829822984f2fe973f34873b55847a4eff090c441766859	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304633433637313737383436383431363632424342433537324144314236464644324142334339454331423442324532343134383339363333424332374138364246343433443742313237433141414338373631353644324634413542303941364234334542304438354535334538453838383037453443444146363336454639344135373633464135414237413539383146363235413334334344393036354138414339324139363138433931383236354344463043433532344132363135413431303139423342423641303536373237423530444643374146393143463035323434303331434230444545463932424239423136434642323931363239373923290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xe83724e38dc06ac36605398c5f2b9ac7276369eb6e332f032aed1a4952df64249707b1554c4e13034fa858ab1059778e1c1a6667385aadb0bcc764dc3381990e	1566559417000000	1567164217000000	1629631417000000	1661167417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fe98301152d263ab1550da60fa29ddb5f0b3fa472105d2052d9aa1245d2aa46c45f920ead5a83778f052528c3aeb4544a748e6fb5199a212373f009d61fc34a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304146384337353632333945393141464345374631304644343641423730394345373930413246393339463043464334363234424239333736413142464332344337333041463234353933313331414637354133453739454433374330384130423338374136374344314342314442323246363342323039373943424338454438463937313233453633464333463842383439443341344241424431413238313641343937393534343936383231324134314446393638424436364131383637453033383131323244344543413233384430373032424531353535423734374643363741453543323742343041313342443441453736363644353542303936363323290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\x20b242f3c683664105ac462cd1e72b883b29b68e7b99a1a267cdf96ff657868e3fefc9f915a7cd3ef9c3dfa2ee8c91510eb86bd1c5e1ce746a35ca11ae735609	1567768417000000	1568373217000000	1630840417000000	1662376417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x52d36b4ccf03cda558db1098c477a0b365191990a65820ebbaee7b82c75864946195462d545c75b618a16cc6fc995f1683e1d3320272a46354cb4c954fbfc37c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304337353233423242414342383834354445464232394337334135394444363739303541304442433344444330384535394431314534434330393144374536434532454441453844353046374132413331333745303439313343333746364445393634324641374537384438423044304146433845423243333945353232334438443238333142333232383246443941343844313945304638434546323446313341343143463232444231373142384642383846344136353739463331373639363032423145413032444236393030333143344244323836374431353744344534443136334242443432354546384243393241394542413033323436444230373523290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xe9ca9f5dc63d5eb6d9b5e9461a35a990b11043208b973ba53546b3a43b0933600979456e2b326a51f64f5b13136c4c7c2de25df2453ae9414c95531eb5049805	1568977417000000	1569582217000000	1632049417000000	1663585417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2dbc767c91cb84229f6a59f8ab9029f0f05fcc76bbe625a6af8674636b362ee55cab9c5932fd83383a0b2d6176a9f636bfeb09cae9ab0a4337e58a857e24fea9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242303545363731313238313936333138443142443042313746344245423844443935323642394341333833323032313231384538323144344438353241303645454230383232334536303733423443333046453732383536354635453535443143373236434637393831303630353039443533393237393138394330363145303144383633443245373635413642413234354338314342344337413139343542463143314543313144323435313546323732384343324438373739353732313838333032324336384531304541333344394343394341464133424630363745374432423235463244464434363830343144373139383737423237333537364223290a20202865202330313030303123290a2020290a20290a	\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xe87c166a461655725f4cb5cc610d2c285c82915517330b4cb40a146a3d296d90c0b27cdc2e292be71fc7efb1f58df2f9b2105071d06b9a34282af3902b0ed20d	1567163917000000	1567768717000000	1630235917000000	1661771917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\x0730bb3c7e1ef9c061ca1483bc74c83b5b27b12631efe30a5f869ce52d639d2e	3	0	1566559452000000	0	1568373852000000	\\xee544a1765265a16734e9dab876129cc1c50244659c6d4ce09c16c2a324e29b4	\\x7b862cd9b986aea4299a2fe1e3e1ad779c69c103dbcaf458479a84e63a172cf1fce2ae3fd8a1470aab869d2ae784b8983510effaa15b782bceebeaec86cfc90d	\\x3adc6fcf2ddfa78bbb9e8731c61ede4491624f133ac776c2ede2c680fc67c8ef92d8c5eb5f1fed1257400f594fba0247316da79a26d27f6cf27dc80124a4b58b	\\x1ffb060f6c0ddc259071ca7159003bc66fbf89c422c0aedf413536723e49f2e6e91bf70dd9a49632ee5426940beb35997d460613e330c5394a6ef4dfffee6801	{"url":"payto://x-taler-bank/bank.test.taler.net:8082/3","salt":"P9PX9G6MSS02RKJTX5A4D3JWZ12NP37R87739BVEPT3G4HE3Z9JWDKDVW458X7ZNT8YJSVMZKA9A12T3W14RNZV19JGZJ9E9HDTP9T8"}	f	f
2	\\x2a60f9bddcf29a5e6434ef91c2cd1d35d2073ca11d3009c58432206e7c94fc36	2	0	1566559452000000	0	1568373852000000	\\xee544a1765265a16734e9dab876129cc1c50244659c6d4ce09c16c2a324e29b4	\\x7b862cd9b986aea4299a2fe1e3e1ad779c69c103dbcaf458479a84e63a172cf1fce2ae3fd8a1470aab869d2ae784b8983510effaa15b782bceebeaec86cfc90d	\\x3adc6fcf2ddfa78bbb9e8731c61ede4491624f133ac776c2ede2c680fc67c8ef92d8c5eb5f1fed1257400f594fba0247316da79a26d27f6cf27dc80124a4b58b	\\x92efe7cb94791b67795d0b7f3664eb8b61b4ad4ee88d03bd9c3a30284d30e8e025468ed41af41dcfb7609be45912c2b9f989abed0926821954a795944d7aef08	{"url":"payto://x-taler-bank/bank.test.taler.net:8082/3","salt":"P9PX9G6MSS02RKJTX5A4D3JWZ12NP37R87739BVEPT3G4HE3Z9JWDKDVW458X7ZNT8YJSVMZKA9A12T3W14RNZV19JGZJ9E9HDTP9T8"}	f	f
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xc273979f7d8c1a626d2eb15eace48ddf4d916dc1024774d97028d69260f6daeb951599f6377957f2e813c5d4d33881912258b0719b8f80ec442357a5ec058b07
\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xacba7509c8fbf778dcd18a996a2ae7b8e6c8c7dc781adf71c5cae2d86b5dcd675c4f6b00f84024d522108a23a93f7e3f15eac4fbc6789508d73b738fc859190e
\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x55e35cb8fc97a84d4791e6794cc3775c242d9fac35cc073b367f1d4a34780b04aed8085a9268cda2c9d52664d821f7fad4c1ea75dc37a27917ccf06ebac31200
\\xbf0541a7d690ac9a2a0bdb1e55f24086b8408c846e35c3c14619c62bdd626833	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xbba3b4b9677e88eb983c3bd1aa654f54beb0aebc15437245c89975a09611cf96c6c1e98edb90265c738e38773add639e7e8055b6799eba613beb9dabd2a69d04
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x0730bb3c7e1ef9c061ca1483bc74c83b5b27b12631efe30a5f869ce52d639d2e	\\xce8c1d02f08e0e27d703187e49f219b5216518e819db6b88c58df9cd417fcc57f2e634b71c264809f008393b55bec8e838a890480df458a42437ca46c720fda3	\\x287369672d76616c200a2028727361200a2020287320233036434444323139303536394535393939384644374439443839344445334641413835304142313034463935324143394243444331454339313237343945304235393834464141364333314335373336314344443242323239453637363243393131423338423346424337333639363044313635414642394533443033344338413333343137423738393833353133463537413938313435464239364634324636454342373642344436324130413130343246313143463243354634453643303142434335464533333943324135414633313038344341374645383343343334423243384330313345344638453138434432383733383846334436414638303923290a2020290a20290a
\\x2a60f9bddcf29a5e6434ef91c2cd1d35d2073ca11d3009c58432206e7c94fc36	\\x413cb63dc48770bf6699e2d6508672bd2a5953ffc25dc4617948cf5da98c4e615587ef0ab59d3af1377e8e245481e2ffe69d8e84b88f643f372805ced4428b4b	\\x287369672d76616c200a2028727361200a2020287320233935373443364239344137443442313241323344374345423437304435374230393535353231454231373346353945313935343635393835424643333239464532424434384236323334324642453943434536443142393536334339343234434636323537344145324146434342303430454342414538454134344136333437443939444532314543453639324231373836383430413330463439314345334238314441383645463133363231424546453346333832453834443735463142453632423742313138444643304139333644383538434537313343373946324537433341434331383631314142453131363432323836423032424330344535343823290a2020290a20290a
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
2019.235.13.24.12-018CWXKN55KVP	\\xee544a1765265a16734e9dab876129cc1c50244659c6d4ce09c16c2a324e29b4	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233352e31332e32342e31322d3031384357584b4e35354b5650222c2274696d657374616d70223a222f446174652831353636353539343532292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636363435383532292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225157324d333959504a3250394d4147425643463542574a3047545734313334344452545737474136333733325151423244305347227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22374245365a4b534456594b52514557594757525743375059384a3850344b524b374233514447514457423338315a33375333515335503635584446485a56384a415830305950414651383134454342444d594432444d4b5a444b5337564a3031344a4a42423252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22585341344d35563534534431435754454b504e5245523939534745353039323642373344394b4739523550324d434a4535365430222c226e6f6e6365223a22564437483234424643503247445a3234524834314235343452595242385850504552504839364745485057594e45483647353830227d	\\x7b862cd9b986aea4299a2fe1e3e1ad779c69c103dbcaf458479a84e63a172cf1fce2ae3fd8a1470aab869d2ae784b8983510effaa15b782bceebeaec86cfc90d	1566559452000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x7b862cd9b986aea4299a2fe1e3e1ad779c69c103dbcaf458479a84e63a172cf1fce2ae3fd8a1470aab869d2ae784b8983510effaa15b782bceebeaec86cfc90d	\\xee544a1765265a16734e9dab876129cc1c50244659c6d4ce09c16c2a324e29b4	\\x0730bb3c7e1ef9c061ca1483bc74c83b5b27b12631efe30a5f869ce52d639d2e	http://localhost:8081/	3	0	0	0	0	0	0	1000000	\\x1326784e3d3be81dc594241967480cf7a9f81e8943c20d4aa55a157579620b43	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2246534241314a5731524b584d31485743584a503939323938534b514e304d48334857344538385a56474547564336594147585a585746574634373736333851504e505a5038573332414d57504a35564e34414b384d3935543236535a3838444746395231383138222c22707562223a2232434b37474b485837464d315648434d34474350454a304359594d5a47374d3938463130544a4e35423841514159423231443147227d
\\x7b862cd9b986aea4299a2fe1e3e1ad779c69c103dbcaf458479a84e63a172cf1fce2ae3fd8a1470aab869d2ae784b8983510effaa15b782bceebeaec86cfc90d	\\xee544a1765265a16734e9dab876129cc1c50244659c6d4ce09c16c2a324e29b4	\\x2a60f9bddcf29a5e6434ef91c2cd1d35d2073ca11d3009c58432206e7c94fc36	http://localhost:8081/	2	0	0	0	0	0	0	1000000	\\x1326784e3d3be81dc594241967480cf7a9f81e8943c20d4aa55a157579620b43	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225148354757393047325a364641344e4d584e5746415654544a37355256455242474a37504844454e334a33515151524d355141444257394e485042364d3851335444485a41513136434631544350583537425259365634505854534139424833595a3554323238222c22707562223a2232434b37474b485837464d315648434d34474350454a304359594d5a47374d3938463130544a4e35423841514159423231443147227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.235.13.24.12-018CWXKN55KVP	\\xee544a1765265a16734e9dab876129cc1c50244659c6d4ce09c16c2a324e29b4	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233352e31332e32342e31322d3031384357584b4e35354b5650222c2274696d657374616d70223a222f446174652831353636353539343532292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636363435383532292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225157324d333959504a3250394d4147425643463542574a3047545734313334344452545737474136333733325151423244305347227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22374245365a4b534456594b52514557594757525743375059384a3850344b524b374233514447514457423338315a33375333515335503635584446485a56384a415830305950414651383134454342444d594432444d4b5a444b5337564a3031344a4a42423252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22585341344d35563534534431435754454b504e5245523939534745353039323642373344394b4739523550324d434a4535365430227d	1566559452000000
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
\\x39be3d8a13828b1e6ae16892eae29142123b844ef4c6d27f740c1b280b4a5332	payto://x-taler-bank/bank.test.taler.net/409	10	0	1568967312000000	1568967312000000
\\x1ee905c938905bf754f7b3276222b1b3e5cc32b7e59118eac44dc7153b3987ed	payto://x-taler-bank/bank.test.taler.net/408	10	0	1568929197000000	1568929197000000
\\x87cdd8e530911c8fb62d96252c353320ee10cc85faf2a16227ce3beaa46fafcc	payto://x-taler-bank/bank.test.taler.net/407	10	0	1568928947000000	1568928947000000
\\x7b88ac2e47ea7d16069aa986e2b317ae174b3a863c42c63e15b0498efb469038	payto://x-taler-bank/bank.test.taler.net/406	10	0	1568928893000000	1568928893000000
\\x0044d1b224b3a6eea5264bfeee1d11cd7d303f02728c0e75d66fbebe97d073ea	payto://x-taler-bank/bank.test.taler.net/405	10	0	1568928688000000	1568928688000000
\\xa12e81176ea8dadbe50c63c1bf01757961d2e768e2f00dacbe7bccf5224deabe	payto://x-taler-bank/bank.test.taler.net/404	10	0	1568928598000000	1568928598000000
\\xf2fb0d6aa54619644c92a7391e4b79db47017440ef88032ac7772d994f102e1c	payto://x-taler-bank/bank.test.taler.net/403	10	0	1568928555000000	1568928555000000
\\x8b08b6956f045c42777b60aabef8f0c0a354409ccf970d00e4e55713c7943d48	payto://x-taler-bank/bank.test.taler.net/402	10	0	1568928453000000	1568928453000000
\\xfa6afd2fc55db401ce4a8512bd58250452332b2663408e9ae10d15483effbeef	payto://x-taler-bank/bank.test.taler.net/401	10	0	1568910289000000	1568910289000000
\\x822fb5586d2fb643b218593c820f074db3aec6bad1dc0cb76fe8f6154f174c99	payto://x-taler-bank/bank.test.taler.net/400	10	0	1568909745000000	1568909745000000
\\xc135bc676a9f3b04a6702ba1882a57943e566e046158a0ca3ada7cf3f325b276	payto://x-taler-bank/bank.test.taler.net/399	10	0	1568900660000000	1568900660000000
\\x02f7f50ac1f2d7d6b20c018f3d9357653eda9861c356f5a8bd6be0c501470468	payto://x-taler-bank/bank.test.taler.net/398	10	0	1568898339000000	1568898339000000
\\x671ba24af73a74eddd46e524cd11f3741d141980038a3c9844d1187ce82bf463	payto://x-taler-bank/bank.test.taler.net/397	10	0	1568898098000000	1568898098000000
\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	payto://x-taler-bank/bank.test.taler.net/396	10	0	1568895815000000	1568895815000000
\\xe6dacd272de8282c0b32344101c61815e3921c4564cc346a991918b21904cedd	payto://x-taler-bank/bank.test.taler.net/395	10	0	1568895620000000	1568895620000000
\\x66ec99ef569ba5b8262b5451943f743d82db4d46d850f56295229bc941e06d0c	payto://x-taler-bank/bank.test.taler.net/394	10	0	1568895335000000	1568895335000000
\\x5a4622282f4ca44630980efeb12cbb2a8c3c46daa0d676186ccdad1103910954	payto://x-taler-bank/bank.test.taler.net/393	10	0	1568895214000000	1568895214000000
\\x1c18ce673522c676d133d3fd38fc525c06f9139256f97733392aa476b38da935	payto://x-taler-bank/bank.test.taler.net/392	10	0	1568894477000000	1568894477000000
\\x4d93a5159d2a5bd6910267a91c3111ac495329410097a1adcf772d3a240df2bb	payto://x-taler-bank/bank.test.taler.net/391	10	0	1568846228000000	1568846228000000
\\xbd46bfe36609883ca276710aa7446bdf49d7a03f005472630e50a0784a53a741	payto://x-taler-bank/bank.test.taler.net/390	10	0	1568846206000000	1568846206000000
\\x2dbb53c2f3627f50b18ec54e15246c7b5f81a15683f53a7177029814f8da8bc2	payto://x-taler-bank/bank.test.taler.net/389	10	0	1568824576000000	1568824576000000
\\x1f4681908ed2f225632346cc1e3b4988ce8fa6c1c8ab179f978b3bcff3c21bf1	payto://x-taler-bank/bank.test.taler.net/388	10	0	1568824226000000	1568824226000000
\\x688b922cfa19931ba3d9030b747bdc2da9716aac4e53f21a15c5988456915581	payto://x-taler-bank/bank.test.taler.net/387	10	0	1568824145000000	1568824145000000
\\x012e41df79ff63a8f39d2817a86bbc0e60f14e70440fbab3c234fc4a8d05d439	payto://x-taler-bank/bank.test.taler.net/386	10	0	1568816698000000	1568816698000000
\\x6c3a52338741d0f462f571f42daf5be81b7a945da9ad871cc9f58ddd700193aa	payto://x-taler-bank/bank.test.taler.net/385	10	0	1568813452000000	1568813452000000
\\xc8e442c5c85ef054a27974ba39c3745c9d017f4bf8e52768c5e8669ba8583e66	payto://x-taler-bank/bank.test.taler.net/384	10	0	1568813422000000	1568813422000000
\\xc9675953172121e16dab952fc11a250245a5682fc6c5cb921cbe1753869d3299	payto://x-taler-bank/bank.test.taler.net/383	10	0	1568813158000000	1568813158000000
\\xc37168aec489a6472db4efc0a85feeb19f6c8cdf1de3723945bba9bd8a7fb634	payto://x-taler-bank/bank.test.taler.net/382	10	0	1568812543000000	1568812543000000
\\x0a26d1acfe138d947700857a157a007c0f8b44cb2cd5387c4e4ba1dc21603e6c	payto://x-taler-bank/bank.test.taler.net/381	10	0	1568812517000000	1568812517000000
\\xc7624530ea124cca7e8661163d6b4016d2a4252b63c901a77a9d1771245da8f9	payto://x-taler-bank/bank.test.taler.net/380	10	0	1568811877000000	1568811877000000
\\xb71c07fdff675806af9e20022b7bf5ec0ec16f0892d3b866436f659da502a25f	payto://x-taler-bank/bank.test.taler.net/379	10	0	1568811745000000	1568811745000000
\\xc8f38a375831272de806e769f96d6c4c142b9c249a5110eb26c35117f69014a3	payto://x-taler-bank/bank.test.taler.net/378	10	0	1568808452000000	1568808452000000
\\xe67cf6c190418a44ff772b5af0075de9f50ecb27d168c907837528575531a747	payto://x-taler-bank/bank.test.taler.net/377	10	0	1568808378000000	1568808378000000
\\x74a4f75e0092c7f48bacfcdc2b3eac5fa93c61548b0bdd053e0bfbb741d9af51	payto://x-taler-bank/bank.test.taler.net/376	10	0	1568806348000000	1568806348000000
\\x62ce130deab667ded5da342d4a7c8a48259c5464e4c11f9a41a155622f736d8a	payto://x-taler-bank/bank.test.taler.net/375	10	0	1568806014000000	1568806014000000
\\x53339a2bc10f6d6dc9f3c275269fab85e67ea25dc2853d5c25898ed41d51331e	payto://x-taler-bank/bank.test.taler.net/374	10	0	1568805562000000	1568805562000000
\\xb2f0675021b8b2b2c82a33d7de06a6188014ef6f641ec1f63b98574adc4a5a79	payto://x-taler-bank/bank.test.taler.net/373	10	0	1568805471000000	1568805471000000
\\x64de8ad09221295cda8823d29797b5335c3c40efd0111a20134fef96bbd9ac9a	payto://x-taler-bank/bank.test.taler.net/372	10	0	1568805285000000	1568805285000000
\\x7140831bef79c6208bca40a3b926a8045cc19cd504f0502261d8d8c5872c9de9	payto://x-taler-bank/bank.test.taler.net/371	10	0	1568805095000000	1568805095000000
\\xe3c38f7f9a1f808655c624f450bd9e1d084ac6448d9f42fbe56dc99c017b176e	payto://x-taler-bank/bank.test.taler.net/370	10	0	1568805033000000	1568805033000000
\\xfc13820602150f5b065d5e8c34ad9c01b28403af35f155bf471c478399382725	payto://x-taler-bank/bank.test.taler.net/369	10	0	1568796092000000	1568796092000000
\\x5d7b8eea903cbe3c4926db1c8c8cce69482ecbc196bd65813388ce3237d77f56	payto://x-taler-bank/bank.test.taler.net/368	10	0	1568795992000000	1568795992000000
\\x77e1ae7a8bfaadc974396088d2fd22fee5398df641a7c3dba0760765875cf6b5	payto://x-taler-bank/bank.test.taler.net/367	10	0	1568792649000000	1568792649000000
\\xdd6e5ecaad109e27520aacc88c39cc4830235f280e8bd11779f38ebee15b237f	payto://x-taler-bank/bank.test.taler.net/366	10	0	1568753032000000	1568753032000000
\\xc856b9453e72fc92eeecf9614cba6acfdfb67a39d1f1017b59803ec0f8f5f8ad	payto://x-taler-bank/bank.test.taler.net/365	10	0	1568752992000000	1568752992000000
\\x119efdc91109466f9d6c8bcf33f956d0046b01380ce66b44ebc3a2902d827d89	payto://x-taler-bank/bank.test.taler.net/364	10	0	1568752884000000	1568752884000000
\\x38cc57b994cf977e00c6c4c25357796e9c2d79b44ce890ce49925cdc6c3d54ac	payto://x-taler-bank/bank.test.taler.net/363	10	0	1568751641000000	1568751641000000
\\x0f352c26485d153ab1654b49a06dc5a47a0b4a14bf4a42cb4cbd18b87fb07374	payto://x-taler-bank/bank.test.taler.net/362	10	0	1568751004000000	1568751004000000
\\xa2f9f8326db9d373b252fcc3a0401bc85b3e97618dc3a432487ef38cd9a6517a	payto://x-taler-bank/bank.test.taler.net/361	10	0	1568749661000000	1568749661000000
\\x46e452f1184d8f6d218534b68b79b8cf6143f1ebaf118a9773546aa200996955	payto://x-taler-bank/bank.test.taler.net/360	10	0	1568749520000000	1568749520000000
\\x47dbd1fbb39cee3d39c117e376c472fa0d0fc6fceccd5f5e978bace5a6af0ab0	payto://x-taler-bank/bank.test.taler.net/359	10	0	1568749286000000	1568749286000000
\\x5941c4d722de161c804086ea30952008b7dd1a6aaf10ef708e2fa122102bae7b	payto://x-taler-bank/bank.test.taler.net/358	10	0	1568748429000000	1568748429000000
\\x051cbec08070f5a75e6de51d35e1aeb7b01a36036a141d2066181092d1d39b11	payto://x-taler-bank/bank.test.taler.net/357	10	0	1568747795000000	1568747795000000
\\x69cff834caa39abbb70820d036158ce6cd3a7f99cb8cec263337660b7383bcee	payto://x-taler-bank/bank.test.taler.net/356	10	0	1568745690000000	1568745690000000
\\x6874b7482af6d0ad81a6d31e6fd08c7ab18503c28e053bda598bfd0acb180c7e	payto://x-taler-bank/bank.test.taler.net/355	10	0	1568745385000000	1568745385000000
\\xdeaaddb0ca6611d9ed384e3b729028fcc22d2fa5764e3843aad3172958ef79d3	payto://x-taler-bank/bank.test.taler.net/354	10	0	1568745018000000	1568745018000000
\\xcbeb4efeee8f755ad46a4cbbe367284d0a31e8355b703eaf3c62a90c25bb6815	payto://x-taler-bank/bank.test.taler.net/353	10	0	1568739569000000	1568739569000000
\\xa044250c7644a8664c2d7dd4f4146946c7d7a74cc9d3c72f24861cca285e515e	payto://x-taler-bank/bank.test.taler.net/352	10	0	1568735421000000	1568735421000000
\\x9ad482c0b94c3fe5403c0093d5609a77e459422795cc0ad7b091f6a28039c281	payto://x-taler-bank/bank.test.taler.net/351	10	0	1568735262000000	1568735262000000
\\x06f725b34ff44ea72a88e0d72d9c754462176850b63841e5ac62eeaa0107da8e	payto://x-taler-bank/bank.test.taler.net/350	10	0	1568732644000000	1568732644000000
\\x4aba78fd0c360bd6bdfb1be8c0033adc09d669e7363ff4f75c7addbead866087	payto://x-taler-bank/bank.test.taler.net/349	10	0	1568731335000000	1568731335000000
\\x003756a82312c1f165d22735a4d91a0931970335d69739be893422b3630bd5df	payto://x-taler-bank/bank.test.taler.net/348	10	0	1568731249000000	1568731249000000
\\x7274923e113464192d274534a3b8dd38572393cf8b6b9a26973ce0c657f830fd	payto://x-taler-bank/bank.test.taler.net/347	10	0	1568719297000000	1568719297000000
\\xb353ec37ab0e6c7b624ae1779404f65f4b7c3dc601a72ca2e0d7f23633946144	payto://x-taler-bank/bank.test.taler.net/346	10	0	1568719279000000	1568719279000000
\\xf6157d960f7b08f4ecd45e8f856090fcb22e069858394a4e7fc97488a88852a5	payto://x-taler-bank/bank.test.taler.net/345	10	0	1568719269000000	1568719269000000
\\x14a56bea0d1606f7636eb8ddcbbfcd8a9479130b22589f154e37ee1575842e1e	payto://x-taler-bank/bank.test.taler.net/344	10	0	1568717156000000	1568717156000000
\\x3eceb3f3a13e966853b828a49921188a0305ccfc88be178f2a76a7e210f174ec	payto://x-taler-bank/bank.test.taler.net/343	10	0	1568717147000000	1568717147000000
\\xf939b9ad110e76af9ee82c5924c812709f610e73f651a120b7b93a35ad8a9462	payto://x-taler-bank/bank.test.taler.net/342	10	0	1568717133000000	1568717133000000
\\xfefdc664b156a8956c22392708056f7771beb50eef224383e7be4e7178a6a8bb	payto://x-taler-bank/bank.test.taler.net/341	10	0	1568717122000000	1568717122000000
\\x0e2d0beab43b0b4fd20157e8b373f21b1fee2a513ebe0fcd18464bfe22889272	payto://x-taler-bank/bank.test.taler.net/340	10	0	1568716930000000	1568716930000000
\\x0425ba60520bbc67ea59dd44fdac94d44aec328d4a504f9a96cd7115d2d7718b	payto://x-taler-bank/bank.test.taler.net/339	10	0	1568716801000000	1568716801000000
\\x6e9d183ab868e7ff9d40138dd763896cb8ee9b230e2de94f73b0d788b738f8a4	payto://x-taler-bank/bank.test.taler.net/338	10	0	1568664673000000	1568664673000000
\\x813db9bd108f103f010eee5c9347a0f8d36da0076ecdfc2aef7e02d643234196	payto://x-taler-bank/bank.test.taler.net/337	10	0	1568664673000000	1568664673000000
\\x59c56af7431f2115a0c22aa89892d170a9a9471db5014e8a824fbc19dcc2d843	payto://x-taler-bank/bank.test.taler.net/335	10	0	1568664673000000	1568664673000000
\\x53d4ea53beca2041bb9b7885f1bf52fbac6b87c44ee7c27b8d5e9eb6d17cc0e5	payto://x-taler-bank/bank.test.taler.net/336	10	0	1568664673000000	1568664673000000
\\xfe59643d79bcc5ecf39a4fda8016c47fd7c8c3635f1bba0a7f6e0c13c134a4b8	payto://x-taler-bank/bank.test.taler.net/334	10	0	1568664672000000	1568664672000000
\\xccc34040dbcf81f0f68cf8c23a5c381c48a8819bf7f0f2d83b24c409023361e6	payto://x-taler-bank/bank.test.taler.net/333	10	0	1568664261000000	1568664261000000
\\x9abf75e6216b8039d914aa14b8c6ef77952b49f8f4b25cc29ee0a6e0cacbfc70	payto://x-taler-bank/bank.test.taler.net/332	10	0	1568664206000000	1568664206000000
\\x76c21837710c2e390b9fe23674f581e87e07ce96e4972c1af82ec1a0847ae95d	payto://x-taler-bank/bank.test.taler.net/331	10	0	1568664157000000	1568664157000000
\\xc725d349c67fd479c2c512e29e33055753da64877d33335fb1b2432e7a32d999	payto://x-taler-bank/bank.test.taler.net/330	10	0	1568664150000000	1568664150000000
\\x2af399b74d0691fb36c2e2b6c00631694b51607c332fd97f29a8d4ecca5c7ef6	payto://x-taler-bank/bank.test.taler.net/329	10	0	1568663224000000	1568663224000000
\\xd58aa182bdc6b8f4463bf392e0bb003325bfb653ad7c18f32d39e38fd20e7ed0	payto://x-taler-bank/bank.test.taler.net/328	10	0	1568662769000000	1568662769000000
\\xe7ac2051b945e977cdb2a613d4434c04c26dd3b102a1bc82d29d08a81ae86b2b	payto://x-taler-bank/bank.test.taler.net/327	10	0	1568662739000000	1568662739000000
\\x2f45b07e937fd0a1feb3d9fcc7aa6c149a96e84338fa251f53f148ceca4b96d5	payto://x-taler-bank/bank.test.taler.net/326	10	0	1568662521000000	1568662521000000
\\x204f1f80cd9e66810bbf74e58cb1838d904ee5941ed205aba33bf9f1e236e49d	payto://x-taler-bank/bank.test.taler.net/325	10	0	1568662509000000	1568662509000000
\\xdb41e9f1ad98bb9bf42c952b770c69c4019fa6c4524f77f92cb4189e96bca115	payto://x-taler-bank/bank.test.taler.net/324	10	0	1568662000000000	1568662000000000
\\x30fba371e70b4ebc0a40f952c43d50d18719b36d310b891059808ea5a21c3710	payto://x-taler-bank/bank.test.taler.net/323	10	0	1568661988000000	1568661988000000
\\x26bd0786ce312f0aec4cc46d8c2a0368974f065f61ecc345c713aa0fc8fa5c2a	payto://x-taler-bank/bank.test.taler.net/322	10	0	1568661972000000	1568661972000000
\\x3e6809817ca4477f5ec4ac74c0bbb76e48448176043a2cb456b0dc455a79632f	payto://x-taler-bank/bank.test.taler.net/321	10	0	1568661948000000	1568661948000000
\\x5a374956e5ff8785db62f4deccdc41d65aad3bb1927344122447acc016aa44f9	payto://x-taler-bank/bank.test.taler.net/320	10	0	1568661856000000	1568661856000000
\\xc3c6006069c05603856ac9e6bf25192f6684467721b96350bdfabc8008bbec9d	payto://x-taler-bank/bank.test.taler.net/319	10	0	1568661738000000	1568661738000000
\\xa5d0664f9f0fdfb4407c6e90712d57e98e824dc1bbc75c79620f68f97d8fd5ca	payto://x-taler-bank/bank.test.taler.net/318	10	0	1568661596000000	1568661596000000
\\x7039453d2727338652a5432ffca59220fe15ebb3e09399d238215311f015107d	payto://x-taler-bank/bank.test.taler.net/317	10	0	1568661538000000	1568661538000000
\\x3428bcdcd2725e6038bba0d5e3189f3caf0c342d55a25d02be539d6ab97cc20c	payto://x-taler-bank/bank.test.taler.net/316	10	0	1568660494000000	1568660494000000
\\x22c98e04feee74f42fba4ab3f00627a118c4d8279df397776bb785903e07ab1e	payto://x-taler-bank/bank.test.taler.net/315	10	0	1568659836000000	1568659836000000
\\x59998f08f6e8f35ea10c51c5700aae79b9f6d6b5f684a377a7f5b2fa6a64a269	payto://x-taler-bank/bank.test.taler.net/314	10	0	1568659436000000	1568659436000000
\\x10dd95f3a5de768b7690839be29f2d8974b0654d13f20b5f7437d768d14f51bc	payto://x-taler-bank/bank.test.taler.net/313	10	0	1568659359000000	1568659359000000
\\x87a6b79a88d73b92f7169010d401421224a6a24b67f40471c4a4761cc0f0bfb2	payto://x-taler-bank/bank.test.taler.net/312	10	0	1568659237000000	1568659237000000
\\x33396f85d648a84af67f09d35532751fa8d90e22b218d0798bd444b12ddac3a2	payto://x-taler-bank/bank.test.taler.net/311	10	0	1568658508000000	1568658508000000
\\x91837011a5b129b2a1ecdaf92cf0fe157479e26044f16705f06aab77c7157879	payto://x-taler-bank/bank.test.taler.net/310	10	0	1568658453000000	1568658453000000
\\x789a55c8a99464a9a7c9c3640e917aa0b4ee760cd49850b1c2c0173480e1486d	payto://x-taler-bank/bank.test.taler.net/309	10	0	1568658210000000	1568658210000000
\\xed4538ca12e87d07f8a036054059c92f875b1fdf5f5cbe12a0dd8c72efc0ef1b	payto://x-taler-bank/bank.test.taler.net/308	10	0	1568658180000000	1568658180000000
\\x1c524fbbb8045eaff17a3935d67f85234f342c943933fb1a0e827f99330bcf05	payto://x-taler-bank/bank.test.taler.net/307	10	0	1568658113000000	1568658113000000
\\x29bb82bedb668a22791007266113a81977b54d9524bfb195812eb4637f449d1d	payto://x-taler-bank/bank.test.taler.net/306	10	0	1568658097000000	1568658097000000
\\xcd9a6ca7e8cf43aabcf1b7e3403139c2ac1d990f78334360d326660ceec8df15	payto://x-taler-bank/bank.test.taler.net/305	10	0	1568657983000000	1568657983000000
\\xbaf74548c792dea461ca5aaf83a69b3a7c9c220a910ab45c286a1ae7df7f1d77	payto://x-taler-bank/bank.test.taler.net/304	10	0	1568657256000000	1568657256000000
\\x7e63f67c1940a9b23d13697aa6582a1fe69581bbd2f1c5098cd3561a989eba3a	payto://x-taler-bank/bank.test.taler.net/303	10	0	1568655719000000	1568655719000000
\\x59bfd4e6dbaa2dfdb58244208e88533a7849ceb3e3e235e427d516ccd69ac5fc	payto://x-taler-bank/bank.test.taler.net/302	10	0	1568655271000000	1568655271000000
\\x268c99db0a689c8fe3544e83745f2c5e3d476ae6e6abe8b62babdcdc62208ee1	payto://x-taler-bank/bank.test.taler.net/301	10	0	1568652065000000	1568652065000000
\\xe7e3ffe3752203bbfa38003e5c6ea51c395c2aa4056b258461f0b24dfbc5a773	payto://x-taler-bank/bank.test.taler.net/300	10	0	1568652002000000	1568652002000000
\\x3b34626e4bd1d6a90a17685dffa13b1de5eaaaefee9dff5b62531b6f9c2b25cb	payto://x-taler-bank/bank.test.taler.net/299	10	0	1568651351000000	1568651351000000
\\x1c50880a086245f96b09dbc9262696d31570b359e9aa847c62dc724e1bbc3904	payto://x-taler-bank/bank.test.taler.net/298	10	0	1568631492000000	1568631492000000
\\xe532b4eaa3a651af35fe482844cf4ee58d9933594e1d07348db46d507d44d136	payto://x-taler-bank/bank.test.taler.net/297	10	0	1568630992000000	1568630992000000
\\xa9508cf654f874b6ac7c137c67a34daadd7566c01452359b0c1974fd866c88a9	payto://x-taler-bank/bank.test.taler.net/296	10	0	1568581997000000	1568581997000000
\\xb6dd4e754c04f7f454fc76eeea421a02db0ab80cadd6e095913aa6a467d08df8	payto://x-taler-bank/bank.test.taler.net/295	10	0	1568581522000000	1568581522000000
\\xc484befd64ce803855834b06e849343331d654f98d2c681c28ae2547533afb07	payto://x-taler-bank/bank.test.taler.net/294	10	0	1568581399000000	1568581399000000
\\x9222bf7c3c95fb9eda6f228d44573407bfbd4c440351830f2d770ac84ab44e36	payto://x-taler-bank/bank.test.taler.net/293	10	0	1568581383000000	1568581383000000
\\x9c377c7a5181ac3a9cd7609eea358428156380615afc3730f87bee265213a756	payto://x-taler-bank/bank.test.taler.net/292	10	0	1568580908000000	1568580908000000
\\xb800e06c8b550082d031a22fde02d8654c27fc7e778c33ab8296349365f72347	payto://x-taler-bank/bank.test.taler.net/291	10	0	1568580857000000	1568580857000000
\\xe57325eea480ac0c9b3434a30b1952ba7deac6d00106b6b9974878edcdf40e7e	payto://x-taler-bank/bank.test.taler.net/290	10	0	1568580734000000	1568580734000000
\\x406b9add395d06468c5828d686b1e78e58f7b6972a25201f452626a4f7dd7d7a	payto://x-taler-bank/bank.test.taler.net/289	10	0	1568580673000000	1568580673000000
\\x89470dee4c3110f9cdc4b7f851b003d1de5417379f473bbdb57454e1997c0a0c	payto://x-taler-bank/bank.test.taler.net/287	10	0	1568580489000000	1568580489000000
\\xda46933e2a492f1c30d56d18176082a5bfb1b9b073abd0cce747f5111137a8b1	payto://x-taler-bank/bank.test.taler.net/286	10	0	1568580423000000	1568580423000000
\\x4c7d9dde23ca42d415f01730f0b19c4ac60560c40095652048b08d2633aa2810	payto://x-taler-bank/bank.test.taler.net/285	10	0	1568580405000000	1568580405000000
\\x5e293aeb6c08a5bcbb1e61df798220451f07f36d00affaa9190775a5f7180caa	payto://x-taler-bank/bank.test.taler.net/284	10	0	1568580055000000	1568580055000000
\\xefe525ec2968cd6845b8c92b02a73c0a0af9af88de003d82ca12deb9e22e9dc0	payto://x-taler-bank/bank.test.taler.net/283	10	0	1568579703000000	1568579703000000
\\xaa87f84bcc4744d63b96cff8436a5f88405dfb5f22a39fd9f9552e8633de9942	payto://x-taler-bank/bank.test.taler.net/282	10	0	1568579523000000	1568579523000000
\\x6ded4375cd71b389104b9096226a89fa1a1846cb7af324842e4a62ca4f32072d	payto://x-taler-bank/bank.test.taler.net/281	10	0	1568579471000000	1568579471000000
\\x1b0e3b898562b405d5989b3617178871f6a0e73f1ca2ade7c293ed29ad760c72	payto://x-taler-bank/bank.test.taler.net/280	10	0	1568578478000000	1568578478000000
\\xd7a6cb733790839a79bed1e9d2ee4b7d8fd66ae70f1645c84edbc535b0d77e33	payto://x-taler-bank/bank.test.taler.net/279	10	0	1568578363000000	1568578363000000
\\xad658d529cb575c0d1d025056f724ad59c2f0efadfc052d4300d4066669f5f20	payto://x-taler-bank/bank.test.taler.net/278	10	0	1568576890000000	1568576890000000
\\xe0b3f02bf670cd068c2483b252c2a47ca204d46b6821ea94f58444345d2004c7	payto://x-taler-bank/bank.test.taler.net/277	10	0	1568571813000000	1568571813000000
\\x66af8e219c20e49afe73128b8687a39e0b8a36f6ce79286714c058e0efdd9669	payto://x-taler-bank/bank.test.taler.net/276	10	0	1568571722000000	1568571722000000
\\x7a218bdf8b9e773794613b3db323fcc95867819c59e24726f7dcf4a13be842d9	payto://x-taler-bank/bank.test.taler.net/275	10	0	1568569242000000	1568569242000000
\\x33453afe5db166f0aa10e4acda686dba022990a845753f3d6d06a61b24cd46a5	payto://x-taler-bank/bank.test.taler.net/274	10	0	1568569167000000	1568569167000000
\\x6b7cede5ceb81248262a13b1d86f2d3b392c18e0c93788fecb5284917523a57d	payto://x-taler-bank/bank.test.taler.net/273	10	0	1568569130000000	1568569130000000
\\xb9d4fdfed4243cf830cebc3195b0d2659649d8a8b4aa885301f83410ae0024e4	payto://x-taler-bank/bank.test.taler.net/271	10	0	1568569059000000	1568569059000000
\\xd5da4a1a66b10dc4e12ab7461fe65023ee0ab2bacbef8fff13a0c0a1de15b66d	payto://x-taler-bank/bank.test.taler.net/270	10	0	1568558061000000	1568558061000000
\\x3af59e0132735e05e27b112d6392ee58a11489cf568bbb5c25bb595405521ff3	payto://x-taler-bank/bank.test.taler.net/269	10	0	1568557887000000	1568557887000000
\\x469bf9c86abb396de1863568f5789599dc6a439450f3f1905f6212bad9f4df9a	payto://x-taler-bank/bank.test.taler.net/268	10	0	1568557765000000	1568557765000000
\\xa5b58e2c15151cc21b2a6d64a01f9358d6c0850067a34f9162351ecac4a57222	payto://x-taler-bank/bank.test.taler.net/267	10	0	1568557594000000	1568557594000000
\\x271ee8933b0258c5551dcdc999da5b708b36ed97dad53800c45bc72d49a39cd7	payto://x-taler-bank/bank.test.taler.net/266	10	0	1568557413000000	1568557413000000
\\x0ccff4d54e80cb3dd68f6e916973508e77051caaae735dd03bc306cfe0afae74	payto://x-taler-bank/bank.test.taler.net/265	10	0	1568557273000000	1568557273000000
\\x6363234157eab234dc540d977e06cf6681bae43e7d2d87beed4739c08f6377c6	payto://x-taler-bank/bank.test.taler.net/264	10	0	1568557141000000	1568557141000000
\\x294eb33578c0dd1135de2b6cc411cd59881a9add9f786995118673899e9c3e87	payto://x-taler-bank/bank.test.taler.net/263	10	0	1568556944000000	1568556944000000
\\xa9d62c09b31f66606af346d0c7e64f77a92954a999e50ffcf574a217e8cb31e4	payto://x-taler-bank/bank.test.taler.net/262	10	0	1568556574000000	1568556574000000
\\xe4d05ad2b0b5e27f3695806e468d54592cd5405e281485196ffa234e63fc68cb	payto://x-taler-bank/bank.test.taler.net/261	10	0	1568556357000000	1568556357000000
\\xf0fda0cd3dda1d31a598c5b9e850a7c54456f8c482af6c1f70b380fd3a659c46	payto://x-taler-bank/bank.test.taler.net/260	10	0	1568556148000000	1568556148000000
\\x695a2de3e0bfdee784b2409b58d18e069f55768745622205a4cb2a99016d976e	payto://x-taler-bank/bank.test.taler.net/259	10	0	1568556033000000	1568556033000000
\\x59ba84ccb16e2a8c0197ae704c9805452d9f91203f0e2a2414865fb43b11b60d	payto://x-taler-bank/bank.test.taler.net/258	10	0	1568555782000000	1568555782000000
\\xf7afb294f813be7682bda81a109f8cebc21c7dde782f897359ce3c4503a915f3	payto://x-taler-bank/bank.test.taler.net/257	10	0	1568554537000000	1568554537000000
\\xa242dcf952f7a0284907e66479db7510f74fff91ce0c318c69e30cc42ac22b28	payto://x-taler-bank/bank.test.taler.net/256	10	0	1568554208000000	1568554208000000
\\xa46479979b59dac9665291fe8c99f56fafd020ab6378518b24a7de4162c0a8fe	payto://x-taler-bank/bank.test.taler.net/255	10	0	1568552868000000	1568552868000000
\\x9307406b793081d213b291e1220b05afa8f8dbe8f0a297729a78228d7b4f5363	payto://x-taler-bank/bank.test.taler.net/254	10	0	1568552853000000	1568552853000000
\\x935c559fcf339b66ea197098e4a7165a373cada72ce6326c6649f21bb2b6958a	payto://x-taler-bank/bank.test.taler.net/252	10	0	1568481483000000	1568481483000000
\\x44884e596728d1764a441c476b6d1600f4e172b82224579a7a9c96d0264db3f3	payto://x-taler-bank/bank.test.taler.net/251	10	0	1568480381000000	1568480381000000
\\xa47e3ec298a912ce770d6f76505ab6bad3bc4f43012ea0a7d02018359ced5e77	payto://x-taler-bank/bank.test.taler.net/247	10	0	1568479255000000	1568479255000000
\\xec426b2ba4cd2036d645ace13c17ec24d034c47123f9b7259b19bddd75bbc282	payto://x-taler-bank/bank.test.taler.net/246	10	0	1568479249000000	1568479249000000
\\xfa6430afd028e2230004a93f5f989f716b04f07f22075c0f71f0de7fb885556d	payto://x-taler-bank/bank.test.taler.net/245	10	0	1568479236000000	1568479236000000
\\x59d46300018a3020106c7635630a580763c94359e41bb30381a5234ffb259462	payto://x-taler-bank/bank.test.taler.net/243	10	0	1568468829000000	1568468829000000
\\x3735705df5fdb4391e2c7308b6efd8aefb2cd17feed80c7d7409b062c4a7020b	payto://x-taler-bank/bank.test.taler.net/241	10	0	1568468789000000	1568468789000000
\\xb7c7fa0443475b8a8f7612bfeb862c3e27c75ef08c2ed9f4ee524e95ba215155	payto://x-taler-bank/bank.test.taler.net/240	10	0	1568468175000000	1568468175000000
\\xe5021623374e4f73a1021b432393316a64b9ff7d8a55b08fa4889bc3ea14cd5a	payto://x-taler-bank/bank.test.taler.net/239	10	0	1568463641000000	1568463641000000
\\x9c9aee06fecf3caa3de9173ae0afb78a3df2361f4a1c98bbaa2fa124dc774d3b	payto://x-taler-bank/bank.test.taler.net/238	10	0	1568418685000000	1568418685000000
\\x0f44803fb16fff27d5b00d0ff093c089dc7671feef732783d98b6057c78795ee	payto://x-taler-bank/bank.test.taler.net/237	10	0	1568418677000000	1568418677000000
\\xcb5d2f41dae0505e076d87da9c209b574708290b94ee53eb7c58b719ff9f8e4c	payto://x-taler-bank/bank.test.taler.net/236	10	0	1568418660000000	1568418660000000
\\xd66e178d92b2c62fec79634fb20a21c5700507111b36bde3a838a9e6afdcd962	payto://x-taler-bank/bank.test.taler.net/235	10	0	1568418560000000	1568418560000000
\\xd0afe6a042bd0d72502690e9b60cc521f101fe75eb854595e3679b3ff1d1f913	payto://x-taler-bank/bank.test.taler.net/234	10	0	1568418554000000	1568418554000000
\\x5180d87442313b7237f1be51fb363524f197ee48e304d04b33f4f46aec114410	payto://x-taler-bank/bank.test.taler.net/233	10	0	1568418501000000	1568418501000000
\\x6189f786c04b5e735b639da1779c9806f86c4dd9324d92cb9ef9dbc6fc515b7b	payto://x-taler-bank/bank.test.taler.net/232	10	0	1568418483000000	1568418483000000
\\x866ec7f2b2123ead9e3500c0ff1f83e386f392c49e2f163ffe697ffd41e0f90d	payto://x-taler-bank/bank.test.taler.net/231	10	0	1568418476000000	1568418476000000
\\x99ecea1c2119254d96d98ef43424b4cbe314fb5bb440e838f6a8a140301bce6d	payto://x-taler-bank/bank.test.taler.net/230	10	0	1568418155000000	1568418155000000
\\x99fbc0d1d5729fd3f0b33736844196fff3d8d278053a60b9b27b47916c3ddd0d	payto://x-taler-bank/bank.test.taler.net/229	10	0	1568418110000000	1568418110000000
\\x5a385ed4779a13d58684098b70882788437bab11102b38ad277aef41baada706	payto://x-taler-bank/bank.test.taler.net/228	10	0	1568417863000000	1568417863000000
\\xb52d325f032b2791d504a532ef9834b033e8ef87eb597bc1a26aa89a2365d212	payto://x-taler-bank/bank.test.taler.net/227	10	0	1568417836000000	1568417836000000
\\x5b63460c0b825d0eaa613f1fca865184b48d04dc105437eb67a267109daf0f02	payto://x-taler-bank/bank.test.taler.net/226	10	0	1568417826000000	1568417826000000
\\x66b219ab9cd23f25e4a3d93fcc72bd87fed8ee4f85fefd13df14c8942018584f	payto://x-taler-bank/bank.test.taler.net/225	10	0	1568417704000000	1568417704000000
\\xbdac584b91a8b1e39cce9f2063853822e248b424f3e68d46af1c6763a7a8c77d	payto://x-taler-bank/bank.test.taler.net/224	10	0	1568417207000000	1568417207000000
\\x8cd98bc82b641ec56a1685ce5e308cf2657281fa219d6325a66221bb16fff090	payto://x-taler-bank/bank.test.taler.net/223	10	0	1568416910000000	1568416910000000
\\x82018291d5681e391d52e11f0fe99dd7af9ba088ef8a04703d47c39c1131661a	payto://x-taler-bank/bank.test.taler.net/222	10	0	1568416778000000	1568416778000000
\\xc77e537ef13fd7c51e61cef89d2022c16b0686ff1c55764969a96ee4c87a3052	payto://x-taler-bank/bank.test.taler.net/221	10	0	1568416490000000	1568416490000000
\\x1d76762600f8bd3f4795f62f03add0c65566e6688292c8646a6b5da12cacf1dc	payto://x-taler-bank/bank.test.taler.net/220	10	0	1568416347000000	1568416347000000
\\xfcfcdc8cd2791777397249d4c3da52e1863f55ad0c6882e2d751bbd405302095	payto://x-taler-bank/bank.test.taler.net/219	10	0	1568416330000000	1568416330000000
\\x3f619c26dc967addb49cae026b9f91709a030e15addc6ca6a5127e72cc930001	payto://x-taler-bank/bank.test.taler.net/218	10	0	1568416200000000	1568416200000000
\\xf5d83929494f27bfa0a816711d37f72cb65f822e8de11668fc52aebf6ce55682	payto://x-taler-bank/bank.test.taler.net/217	10	0	1568416175000000	1568416175000000
\\xa4d33108e549c5f07de36bb4d46529b1e368ace2ad4c34606eb1dfff199efd6d	payto://x-taler-bank/bank.test.taler.net/216	10	0	1568416170000000	1568416170000000
\\x7c002a0774ba18250483639e653c545867bd19c9a7e5e469f6867be5322a772b	payto://x-taler-bank/bank.test.taler.net/215	10	0	1568416163000000	1568416163000000
\\xb4de597a51faf7dba502d6b7d4d08809f423fe4e25218590e3fb05ccfc2824cd	payto://x-taler-bank/bank.test.taler.net/214	10	0	1568416159000000	1568416159000000
\\xf7719f9def9a2234ca81e166c0233b2468cbacd10b699d3cf61a6bd46c032a81	payto://x-taler-bank/bank.test.taler.net/213	10	0	1568416113000000	1568416113000000
\\x6bf8404ce889b919973f0dadfd10a1497e3fd6e794b7e64c6df8011a37511623	payto://x-taler-bank/bank.test.taler.net/212	10	0	1568416107000000	1568416107000000
\\x5608e9a6b49d5da56c6e306f6f35d37d71f5cd1f709a4ea4403ca1335b952dbb	payto://x-taler-bank/bank.test.taler.net/211	10	0	1568416095000000	1568416095000000
\\x093d02b628a9974e33fcf8a6d5fc6d74c70427960d524fd8674977d819163e72	payto://x-taler-bank/bank.test.taler.net/210	10	0	1568416086000000	1568416086000000
\\xbb61ab42b47a032fb8809a0fd1b2cd13f509c1e922863d9e84ac188bba2ba4a2	payto://x-taler-bank/bank.test.taler.net/209	10	0	1568416071000000	1568416071000000
\\x231459f058a65e3e280e888cec88737c2452fcdd1317322b92898372c8eee53f	payto://x-taler-bank/bank.test.taler.net/208	10	0	1568416067000000	1568416067000000
\\xb800dddd6ca1525b45937f3638762afba97df01c8fd68589b332cc6af8c17f6b	payto://x-taler-bank/bank.test.taler.net/207	10	0	1568415497000000	1568415497000000
\\x6edc8a322e33a069a0c0fe3ad6461c677dee1f9445deb38e243ce53bce2c5606	payto://x-taler-bank/bank.test.taler.net/206	10	0	1568414925000000	1568414925000000
\\x12fba7c03a70173a50b46399a5d848b0639b0c59f4465af5a923fecf0306356b	payto://x-taler-bank/bank.test.taler.net/205	10	0	1568411236000000	1568411236000000
\\x8b90d565724439977467feb78f95468ca325a6a583ec42eb9e528ed9ee67acfd	payto://x-taler-bank/bank.test.taler.net/204	10	0	1568406062000000	1568406062000000
\\x52b90c06be123b6979ec5d9ba1032013ce60a91dacddbecafee7302d9ce709b7	payto://x-taler-bank/bank.test.taler.net/203	10	0	1568400506000000	1568400506000000
\\x92077db0eb754e8074b64199e68906e04614d790042aed5d9cc84db1f80e8aca	payto://x-taler-bank/bank.test.taler.net/201	5	0	1568379510000000	1568379510000000
\\x31b91dbf4e89506f09d918dffa3a1800813f8e7fe1a7356c3a92681f62b9066f	payto://x-taler-bank/bank.test.taler.net/200	10	0	1568372128000000	1568372128000000
\\x6e846e63f3d4d2639febf8c3ef0bc3ff60acdb5d81de4d83e02d5ae36885a82b	payto://x-taler-bank/bank.test.taler.net/199	10	0	1568372022000000	1568372022000000
\\xd569191f67bff925e2e14f1a15e5392546b5bbc64ff1e7de72ad32c47a3959c0	payto://x-taler-bank/bank.test.taler.net/198	10	0	1568371849000000	1568371849000000
\\xefeeaed84eef3241f90f8713642986f5a806911a899d461f4c88e8b0af61ffe4	payto://x-taler-bank/bank.test.taler.net/197	10	0	1568371820000000	1568371820000000
\\xc1d651a7160f70ad594d9ee5cd188d42687fe99db4c41a61fe82633e626fa083	payto://x-taler-bank/bank.test.taler.net/196	10	0	1568371810000000	1568371810000000
\\xe57f5d46511d0e766c18a6ca9fc54d3283a2bb102eb8bfdf8e32266c74bcc241	payto://x-taler-bank/bank.test.taler.net/195	10	0	1568364092000000	1568364092000000
\\xf04ba9bc678428207d91776a9464b3b108b58c38fa268bc1b7a227eda49819e8	payto://x-taler-bank/bank.test.taler.net/194	10	0	1568364021000000	1568364021000000
\\xed16aa8942792639654d1f6023e09d1d650f2b8c93a63c1009efe130b00bb1ca	payto://x-taler-bank/bank.test.taler.net/193	10	0	1568360830000000	1568360830000000
\\x0a0d4eb5d1abbb8cea07fee2ba1ed90bd1ebc7e22daf4a368a03cb1ba3ace1ad	payto://x-taler-bank/bank.test.taler.net/192	10	0	1568359272000000	1568359272000000
\\xed3384e769e63bbb3a3b0e7e0d7a695c87cb83beb68a07aea69dbd28a02a00f0	payto://x-taler-bank/bank.test.taler.net/191	10	0	1568356583000000	1568356583000000
\\x6fceae6ef52dfe039f42c029ded6f5083158b76460d1a4415de2a13e0d6b141a	payto://x-taler-bank/bank.test.taler.net/190	10	0	1568354996000000	1568354996000000
\\xe079bd72ea08e0f54d38e00c0eebecf518d7e81b60d03082e929fdf76954aad4	payto://x-taler-bank/bank.test.taler.net/189	10	0	1568329346000000	1568329346000000
\\x9be84bc3757bc122966d499f582bb9f053dd837cffebec5317e28f0076820ac9	payto://x-taler-bank/bank.test.taler.net/188	10	0	1568328931000000	1568328931000000
\\x5e203725f5da7b3a43eb8c55bf3bc7674a8c9aaf19e5706516da2d337a623e83	payto://x-taler-bank/bank.test.taler.net/187	10	0	1568328925000000	1568328925000000
\\xf5d0a679138775b0bd2c7025d52533a4d3c663a2a8e790fbcbf1323c7038edea	payto://x-taler-bank/bank.test.taler.net/186	10	0	1568328866000000	1568328866000000
\\x352ca9fad07eb58ff536e649e5257e8153c2d6388f4b50caaf6464d8c312ffa5	payto://x-taler-bank/bank.test.taler.net/185	10	0	1568328797000000	1568328797000000
\\x2e199e3752fa0de89b8336f28ac07d39e835b663da6d875321332681524ef8b2	payto://x-taler-bank/bank.test.taler.net/184	10	0	1568328667000000	1568328667000000
\\x354145bcdd8f777d8f7450e7364e6546d3b5bb2b81e285ce342e2d57022acb5a	payto://x-taler-bank/bank.test.taler.net/183	10	0	1568328594000000	1568328594000000
\\xf8ad117b767116b4b6ecd1946e5c8258a9d0e26f10f5aeb83a2c96d9a4e801b5	payto://x-taler-bank/bank.test.taler.net/182	10	0	1568328286000000	1568328286000000
\\x2d841e2844b84613d06e1871ce1ff7c7aeb6e6272d643d95cf83b800d83f6fa5	payto://x-taler-bank/bank.test.taler.net/181	10	0	1568328249000000	1568328249000000
\\x099c38804d748d134f237668a8c22970981a1666cee497cab15a5b3761d95fe2	payto://x-taler-bank/bank.test.taler.net/180	10	0	1568326803000000	1568326803000000
\\x0534b703fcf4fb1bcc5c98894919ce8f6c647409c80ecb2f6784ea736f52a258	payto://x-taler-bank/bank.test.taler.net/179	10	0	1568326729000000	1568326729000000
\\x4ef3a8013f6c1fd371954afdf7db5831e2a4b08a24a46d47ce0d0fe71db27450	payto://x-taler-bank/bank.test.taler.net/178	10	0	1568326453000000	1568326453000000
\\x7e5c973417676e8adab516ab8ae8e867a929f1d5b49f19fa01cb129e1333557a	payto://x-taler-bank/bank.test.taler.net/177	10	0	1568325553000000	1568325553000000
\\xdaf21c4d7d0506e761794bfd54286da9cccfbd5dcffec91d4de685ddeb2d9874	payto://x-taler-bank/bank.test.taler.net/176	10	0	1568325480000000	1568325480000000
\\x37e05777be1d12227329799c20ceb6392c437fa7ff2f7cd9b73fb6942d97b674	payto://x-taler-bank/bank.test.taler.net/175	10	0	1568324546000000	1568324546000000
\\xab61e6dc949dd1f35b2bcf8aa92155a61b37dc8ff002513db10988d72c10f85c	payto://x-taler-bank/bank.test.taler.net/174	10	0	1568323859000000	1568323859000000
\\x9d7bdee2ad68d7850d99dc3009925e3fff8faf821c782c75b9e58d8401f492a6	payto://x-taler-bank/bank.test.taler.net/173	10	0	1568323193000000	1568323193000000
\\xfbcab337efa5cad7f030026dd568ce0a9f6b32a3f0647b6c23d9055c4272ae38	payto://x-taler-bank/bank.test.taler.net/172	10	0	1568322988000000	1568322988000000
\\xd24bceae2f137c7a7a33a7e27490f2ee051ca8303fee7d4dd8e78d7a1f0aee62	payto://x-taler-bank/bank.test.taler.net/171	10	0	1568322789000000	1568322789000000
\\x5039d714051dc54f8a12d638d99d6ee2cbba8f84417d239ba13a6dae52a106d8	payto://x-taler-bank/bank.test.taler.net/170	10	0	1568322728000000	1568322728000000
\\xe3885032e24de4aff2214d768134ee11d500559f69b92befe92a9b475fdbbeee	payto://x-taler-bank/bank.test.taler.net/169	10	0	1568322655000000	1568322655000000
\\x92f04e72829581397d5d7af2cfbe8c1eb98769ed2a1dc49f9502e4efb1387ca4	payto://x-taler-bank/bank.test.taler.net/168	10	0	1568322583000000	1568322583000000
\\xcbb9acd062ab443328e6050dbe93e2b8f84c6e2d06b4d98e8aace06251e06033	payto://x-taler-bank/bank.test.taler.net/167	10	0	1568322477000000	1568322477000000
\\xe9cd9bd7e64730ffcca680c79dc186180f44228b2b64146e3e98689c074bf5a7	payto://x-taler-bank/bank.test.taler.net/166	10	0	1568322277000000	1568322277000000
\\xe9475fffced36d5aa6e26073dd28ccc50f2ca4448b3089ecc9c13030abd8f60b	payto://x-taler-bank/bank.test.taler.net/165	10	0	1568322056000000	1568322056000000
\\x87df20e293f6c021efdb3408e1f3121f79a5f1000cbdd3d2b09eade6969f07c8	payto://x-taler-bank/bank.test.taler.net/164	10	0	1568321984000000	1568321984000000
\\xddb8dfe63ae9995f4846435d10bbb0b27887c5bd911082781c4efedd0df40f67	payto://x-taler-bank/bank.test.taler.net/163	10	0	1568321733000000	1568321733000000
\\xf236ae1b03f5896bb57da63548778c065c31c5d30ca2e1b257b98e8a40a1f498	payto://x-taler-bank/bank.test.taler.net/162	10	0	1568321019000000	1568321019000000
\\x245663abb3929008134cfadcd585d8c30189eac85a59ac3f63b57ee150394031	payto://x-taler-bank/bank.test.taler.net/161	10	0	1568320829000000	1568320829000000
\\x7920ef3246557b9add917c3b24df7557e597b9ea132d7a6ade8147463f20d88e	payto://x-taler-bank/bank.test.taler.net/160	10	0	1568320502000000	1568320502000000
\\x383faa3efbad6ba618b9a0518c726b968c093da880aa325e0815c26d302baa8d	payto://x-taler-bank/bank.test.taler.net/159	10	0	1568320449000000	1568320449000000
\\x0c5cd55b9766b103527762452a1e81367c77bf6d24403a15b94ea0fa87904776	payto://x-taler-bank/bank.test.taler.net/158	10	0	1568320045000000	1568320045000000
\\xd0310cbff1f595d844e540ff10e9e2de78fcb27fdba221f4243ec5bf69585c82	payto://x-taler-bank/bank.test.taler.net/157	10	0	1568320015000000	1568320015000000
\\xb21a34488c76adf57605deef27a970d6d9d33da99fd10d5b34f971283282b936	payto://x-taler-bank/bank.test.taler.net/156	10	0	1568319524000000	1568319524000000
\\x038996dfe9ad38f23e619fd7633f3074e88b03d48e59d818047613fe6617f725	payto://x-taler-bank/bank.test.taler.net/155	10	0	1568318945000000	1568318945000000
\\xba2946c6883d1ed6f2770b5902b2b08f6ee0a02148b277b60a085f88118d3ddc	payto://x-taler-bank/bank.test.taler.net/154	10	0	1568318879000000	1568318879000000
\\xb233d5a9840e928cb977bceb516306951f3690c14183539824dd61ee466f08c2	payto://x-taler-bank/bank.test.taler.net/153	10	0	1568318181000000	1568318181000000
\\xa42e64a59afcf6bb9f1c76f9cb00613f067bc49f5e81b8e242d813bafccea2fc	payto://x-taler-bank/bank.test.taler.net/152	10	0	1568315915000000	1568315915000000
\\x3ec53b2ead912ef64ac90c74d5a68e5b60ae65f0249af37ea6eb9e05b9164898	payto://x-taler-bank/bank.test.taler.net/151	10	0	1568308050000000	1568308050000000
\\x21d76dcb3902f1dbdde706d80a37b852666435bbeca78bfdc5cef62d72686d43	payto://x-taler-bank/bank.test.taler.net/150	10	0	1568293486000000	1568293486000000
\\xf1c90d032747f3cc1d8738eb9c888c1e4013f9e7064ffd521a7eaded85cfbc9f	payto://x-taler-bank/bank.test.taler.net/149	10	0	1568220556000000	1568220556000000
\\xaf086d1b12d87e90235d15156afdafefe8fcd38f4de456e9bbfeb62b3d6c3ad4	payto://x-taler-bank/bank.test.taler.net/148	10	0	1568219633000000	1568219633000000
\\x06ac13492eace96f3e5a49e44e0f18c4a356c77b1d4a8e856b976d9e9a436edc	payto://x-taler-bank/bank.test.taler.net/147	10	0	1568219489000000	1568219489000000
\\xea06a92933ce6035f37c58c4476a5b661228594d98b62e4b8f8c2458fe451303	payto://x-taler-bank/bank.test.taler.net/146	10	0	1568219435000000	1568219435000000
\\x64a12dded192a4f8edc3614e4acf52fbe27c78cbed3ab815f4627723ca14e4ab	payto://x-taler-bank/bank.test.taler.net/145	10	0	1567621794000000	1567621794000000
\\xfb949fb3cf8195cd6424b1475ea365019a9a4fbb25041e94af644e201c7c83d6	payto://x-taler-bank/bank.test.taler.net/144	10	0	1567621602000000	1567621602000000
\\xe566a9c140e79572592dfeb3dcf5cea94c9dd8da30dc292d8fe44a284ce5d481	payto://x-taler-bank/bank.test.taler.net/143	10	0	1567620402000000	1567620402000000
\\xc2cabf67c5f7bdc043a7f62ed26cb12fd43b1492aabb44bf5db7f0d70e57dbf8	payto://x-taler-bank/bank.test.taler.net/142	10	0	1567116022000000	1567116022000000
\\x07339becf40893d3ae5d1240e79f1f24c8289ce9ba616c570c50f7f58cd81169	payto://x-taler-bank/bank.test.taler.net/141	10	0	1567115004000000	1567115004000000
\\x23e715a7d521c72f5b14338fea8ef018b42e255c3047d0a381ba1b892951a584	payto://x-taler-bank/bank.test.taler.net/140	10	0	1567114996000000	1567114996000000
\\x18191bb360a5f0a52525101988c41ed8c9244511d8813371023d44164dd3ff9b	payto://x-taler-bank/bank.test.taler.net/139	10	0	1567113527000000	1567113527000000
\\xbf0ff9a0ee337e7af907db7c46888d79a3f4e0dcc96ee1476a8bd4bb0b063a30	payto://x-taler-bank/bank.test.taler.net/138	10	0	1567113433000000	1567113433000000
\\xdd974f8782ead8c4f65996e45e14cbdedd05b5ff194f2e069086c2918819b75c	payto://x-taler-bank/bank.test.taler.net/137	10	0	1567113353000000	1567113353000000
\\x24bfdf65d4f1f9d4569b886e727b9aa0dc6880614899b27f5663d8b72e1b583e	payto://x-taler-bank/bank.test.taler.net/136	10	0	1567113304000000	1567113304000000
\\xf03f57d32b04d85adbce1409248b6b5fb37321cd9d9cf87501d21db209336cdf	payto://x-taler-bank/bank.test.taler.net/135	10	0	1567113214000000	1567113214000000
\\xb808d9b7228568c2da8a58e1f0f5bab7af279d1db94592f1117e42163aeee7be	payto://x-taler-bank/bank.test.taler.net/134	10	0	1567113025000000	1567113025000000
\\x96b4b1dda4cf071443b4981f1d19d2f2f2e18c134355b9fee726e8f36bbdd2da	payto://x-taler-bank/bank.test.taler.net/133	10	0	1567112977000000	1567112977000000
\\xc18211fa8c81102e6fc987ba80a04caa028b1982b816a5d2785614d6ebec3c96	payto://x-taler-bank/bank.test.taler.net/132	10	0	1567111961000000	1567111961000000
\\x7085f00e9a48f4678899788358172b7447cd456c276a20d7313ca474be88b8a7	payto://x-taler-bank/bank.test.taler.net/131	10	0	1567111847000000	1567111847000000
\\x6803c62ef4992666d21fd5571e2807134d1aaa6f7fbb7f8333ddbab7910e0a00	payto://x-taler-bank/bank.test.taler.net/130	10	0	1567111766000000	1567111766000000
\\xd9639612a99db4d4527d907179d1649575ade0db21205bb984928d59916ff575	payto://x-taler-bank/bank.test.taler.net/129	10	0	1567111738000000	1567111738000000
\\xb4a2cee738ce45ecc226c07766148a710e68875ae06b92447f79d3615a279da7	payto://x-taler-bank/bank.test.taler.net/128	10	0	1567111678000000	1567111678000000
\\x66f3faced265ce5d6c8b67ca3566edf511e61b0caada94bf08ba538d01357b70	payto://x-taler-bank/bank.test.taler.net/127	10	0	1567111633000000	1567111633000000
\\x48df8b7cfd2999012b0004f8d0746d4c1ccf02051b6c55b071bf0bc3f92aee9c	payto://x-taler-bank/bank.test.taler.net/126	10	0	1567111611000000	1567111611000000
\\x548a4bc745f4033c770ed431c2321bbe70d609d881190f970251bda60052c5a5	payto://x-taler-bank/bank.test.taler.net/125	10	0	1567110765000000	1567110765000000
\\x63a477040824f3cd55ac8dbc628274a9107608c423fc51643ac25d2ed61d0de8	payto://x-taler-bank/bank.test.taler.net/124	10	0	1567110351000000	1567110351000000
\\x2c1b8d0b80acb5f6e3049190ff613726a4b5441553b3d3ec77deb232594e7218	payto://x-taler-bank/bank.test.taler.net/123	10	0	1567110305000000	1567110305000000
\\xd78dde36de2139fa86f2a0f7bf8a13b2f654d9fc3cd303ebb2eab186cb9f0040	payto://x-taler-bank/bank.test.taler.net/122	10	0	1567110171000000	1567110171000000
\\x1fdc52e5e5aaf87add91e7a1fec0fbf332ce7bd9c9d64154317e670798fe7fbb	payto://x-taler-bank/bank.test.taler.net/121	10	0	1567033624000000	1567033624000000
\\x1380f5e214357cb2e7717dff93edbdfe1a0ea3d38abaab37ab80e1c0c68ae71a	payto://x-taler-bank/bank.test.taler.net/120	10	0	1567027799000000	1567027799000000
\\x954518ac86a57cd7f8e87ee130a700fa82dfc8bebfe203ca3b74d2cd17e1cb26	payto://x-taler-bank/bank.test.taler.net/119	10	0	1567027748000000	1567027748000000
\\xbb8902b13a6baac9f348816b3c3b9ec1b3c3c806416a64c73dcc454e09227a92	payto://x-taler-bank/bank.test.taler.net/118	10	0	1567027440000000	1567027440000000
\\xe4d26be5cacceef7912af71ecde66d520cb080386e12e595f003247e1f936722	payto://x-taler-bank/bank.test.taler.net/117	10	0	1567026602000000	1567026602000000
\\x16b8099673434e13daef88b354ddde89a8ab8803a78a262ee01ff241af07951a	payto://x-taler-bank/bank.test.taler.net/116	10	0	1567026500000000	1567026500000000
\\xcd29f44596d41578562294edaa5f9d225da864c18d222ebc64186656208213c3	payto://x-taler-bank/bank.test.taler.net/115	10	0	1567025876000000	1567025876000000
\\x24f5e83ab46b9b876a6d044bdbfd86edd0d5ac06e34f822f73537f9e86ddd27e	payto://x-taler-bank/bank.test.taler.net/114	10	0	1567025847000000	1567025847000000
\\xa8120c712e0045d452667af538614c2ede7fa93e574b98c2568dc94f1200ed2f	payto://x-taler-bank/bank.test.taler.net/113	10	0	1567025769000000	1567025769000000
\\x8de9216933cf74b32a0ba183c5d47f07deb8d1ba6aeab2558d27933f8f46251a	payto://x-taler-bank/bank.test.taler.net/112	10	0	1567025697000000	1567025697000000
\\x86d56a0cf7a3981f71b607a9673ee2fe4ad3a8710274073cbe9dfb7ad73a2510	payto://x-taler-bank/bank.test.taler.net/111	10	0	1567024729000000	1567024729000000
\\x536fbc82c3257adfb45db4a7c3fea6661442a2edf4eb3413121e86916d84c559	payto://x-taler-bank/bank.test.taler.net/110	10	0	1566958033000000	1566958033000000
\\xc5665b33302b94735b0f53fabe3e4b28005be2cd6ea7b9f8ee133bc35f397ed3	payto://x-taler-bank/bank.test.taler.net/109	10	0	1566957974000000	1566957974000000
\\xa85e72dc53fad0966b30f675487aac5810e20b3bf7f36c63233bea2d1c9370e7	payto://x-taler-bank/bank.test.taler.net/108	10	0	1566957801000000	1566957801000000
\\x58964c1bcebf6b5513e15eb0eef739d38f1478e1cd53bf661342b9c62038cbe2	payto://x-taler-bank/bank.test.taler.net/107	10	0	1566957759000000	1566957759000000
\\xd3be87219e455c130fb5d5976ec829cdf39359a7d0a3e37cdabd0e42f2fad9b2	payto://x-taler-bank/bank.test.taler.net/106	10	0	1566957604000000	1566957604000000
\\x62d223b400193c59c2e72fbccbe09b9184ac7c1a028da0035d53461ca495555e	payto://x-taler-bank/bank.test.taler.net/105	10	0	1566957547000000	1566957547000000
\\x00c831aa5b629c775dc9a0175875c435262392e8ec98c820efab3c40f59c3fe8	payto://x-taler-bank/bank.test.taler.net/104	10	0	1566957467000000	1566957467000000
\\x1997040916524f5640cc195c47cb5c032164e8c192fa255e85a3ae9d5800660c	payto://x-taler-bank/bank.test.taler.net/103	10	0	1566957397000000	1566957397000000
\\xa3e78ad0d30b125cd2d8a415ca3b9a43b971ac8e43647a68064b78943ef65e7c	payto://x-taler-bank/bank.test.taler.net/102	10	0	1566957375000000	1566957375000000
\\x43204e72736000d5ddee27e781d5ad4b45bfde4b3e83173311189ab720af0dca	payto://x-taler-bank/bank.test.taler.net/101	10	0	1566957344000000	1566957344000000
\\xa6ea849bc978b07d539c37404ce74dafb28b94d46d3d929a9ddba72d176fc5fb	payto://x-taler-bank/bank.test.taler.net/100	10	0	1566957236000000	1566957236000000
\\x35641ad074a9b19579b03e68c2bd128dd15deaf8684af5c4a346801372d41b90	payto://x-taler-bank/bank.test.taler.net/99	10	0	1566957190000000	1566957190000000
\\xaae06b233c96780d6afd620b1edd6f821d14a5bf432fbc5f4aeb689e7fe3d938	payto://x-taler-bank/bank.test.taler.net/98	10	0	1566957154000000	1566957154000000
\\x4c6d212fba5c61423aad80c8af8b1d5f3c94b267d920f53851caadf2166d49b0	payto://x-taler-bank/bank.test.taler.net/97	10	0	1566957128000000	1566957128000000
\\xd0c7accb37f6345703dfb0502fa150066094c681ed319b1dc2fcd234eb6fb767	payto://x-taler-bank/bank.test.taler.net/96	10	0	1566957088000000	1566957088000000
\\x64aed8c33abf2c05cefa50c0ecaf5e1f20201e747be1339b8d04fbb29b59cb57	payto://x-taler-bank/bank.test.taler.net/95	10	0	1566957083000000	1566957083000000
\\x69958928499e2c55da1ea6fb7833bd6a3e80962996c4a821fe95d05b58f96a26	payto://x-taler-bank/bank.test.taler.net/94	10	0	1566956929000000	1566956929000000
\\x5cb50417e9ab996297eb90960b33772f344ae83bc6ef32ebe96318d09cb331f0	payto://x-taler-bank/bank.test.taler.net/93	10	0	1566956914000000	1566956914000000
\\x06ea81e28c450fd05b5a0c912fef872fe3adf22a8ca70425cfd38ff2a65649e1	payto://x-taler-bank/bank.test.taler.net/92	10	0	1566956897000000	1566956897000000
\\x81f75ad9675c95ba5078825b565c0f824f40359308975309996a4da4a5644f10	payto://x-taler-bank/bank.test.taler.net/91	10	0	1566956890000000	1566956890000000
\\xb2c11ab01be7ce2856f045ae71e075b7773c0ee212d4fe17a6c3b7357610517d	payto://x-taler-bank/bank.test.taler.net/90	10	0	1566956883000000	1566956883000000
\\x9656ed83ad3aa5cc92c0f8164a1be450f5f275de8ac3cbe3269a5b2bc67a4e8c	payto://x-taler-bank/bank.test.taler.net/89	10	0	1566956855000000	1566956855000000
\\xb0f9afccc0e0e6db8ff80daafbe7e3402de21e2f37d57f22348397c5d5d28940	payto://x-taler-bank/bank.test.taler.net/88	10	0	1566956844000000	1566956844000000
\\x302417b3226366b7893c3cf6ea0a9914d7f12ee9c4f7e68f4b0a743dddc2daad	payto://x-taler-bank/bank.test.taler.net/87	10	0	1566956797000000	1566956797000000
\\xbebc635004c1523c36f749753b8d7df3e3a535d657529c88edda82aa8372688e	payto://x-taler-bank/bank.test.taler.net/86	10	0	1566956735000000	1566956735000000
\\xd97382f3adeb334efc19beb626b79a465cf10e6722370f4158811962ea18bafa	payto://x-taler-bank/bank.test.taler.net/85	10	0	1566956686000000	1566956686000000
\\x1da515d261a0b861b1c937b34bf6cbf0dfe0baf10646daec02035c888775be0f	payto://x-taler-bank/bank.test.taler.net/84	10	0	1566956680000000	1566956680000000
\\x9f5bf80861719ced68d14c652154ef31251800dfb9b9d131fd211072cbe1dfe0	payto://x-taler-bank/bank.test.taler.net/83	10	0	1566956673000000	1566956673000000
\\xf405b7257a8a5538d422ef6357ad1bf283cc4c11fffc5d0cfa766f72513618b6	payto://x-taler-bank/bank.test.taler.net/82	10	0	1566956613000000	1566956613000000
\\x22f8a5abcfd602cc882981bb71b6369295be2134d32634f3f977149bcdcb58f0	payto://x-taler-bank/bank.test.taler.net/81	10	0	1566955610000000	1566955610000000
\\xe28be2d1c6b322cf70742df0d1770adab4273af10f2a141ff703bbd24a9a9ac8	payto://x-taler-bank/bank.test.taler.net/80	10	0	1566955571000000	1566955571000000
\\x6a0d97fb945b3b91e17b1e40f3e8b6d7b595a57e4bbffbea232987e427b5a1d1	payto://x-taler-bank/bank.test.taler.net/79	10	0	1566955531000000	1566955531000000
\\xfb87bd1deed3e5c30cdd323ef440e77e42d859262962e9f99c03a5c740e4afaa	payto://x-taler-bank/bank.test.taler.net/78	10	0	1566955463000000	1566955463000000
\\x312118463312133bf9537123a3930ac4a4d2c245baea11dd8fd32fd8351bed29	payto://x-taler-bank/bank.test.taler.net/77	10	0	1566955398000000	1566955398000000
\\x4685b36210f4a6c7e87d9f88b5a45f834a0d5b58c9d138fd705aaf442e9ad8c4	payto://x-taler-bank/bank.test.taler.net/76	10	0	1566955271000000	1566955271000000
\\xfb380400ea4f5a8fbc5b8bb4a09b779aaf217474955c02d02e6c2f7067293e2e	payto://x-taler-bank/bank.test.taler.net/75	10	0	1566955253000000	1566955253000000
\\xbc40482ef0b8339c6ca1a7fdb65773a0e8a025c9c132fb6be01e73f7034e6e55	payto://x-taler-bank/bank.test.taler.net/74	10	0	1566954949000000	1566954949000000
\\xd681ec996bf4ca985c7fa9577709158416c88988a29f20d8ea16dfbc27e494ff	payto://x-taler-bank/bank.test.taler.net/73	10	0	1566954783000000	1566954783000000
\\x4deda68ee9c75e3eafa0727067c4778ca01a8e2adc85eb1a8b45035552a98578	payto://x-taler-bank/bank.test.taler.net/72	10	0	1566954376000000	1566954376000000
\\xa83105590f3561f861081fcfd5f885a01585b325ffb3263c6a7c9c8d2a10c34c	payto://x-taler-bank/bank.test.taler.net/71	10	0	1566954367000000	1566954367000000
\\x54b48db3c7833a4a43d7433a7443c0a43ca5eccdae6760937e9fe4c074b2a3da	payto://x-taler-bank/bank.test.taler.net/70	10	0	1566954008000000	1566954008000000
\\xf4ce5a6636d9042b66f1633ae30b2aa5cd262a189ed20f793f72307dc9c248f0	payto://x-taler-bank/bank.test.taler.net/69	10	0	1566953834000000	1566953834000000
\\xe6aec2213578fe4de5fee32f82d79ce13f168f9ddd1861ea50c2f13d62c9f4ad	payto://x-taler-bank/bank.test.taler.net/68	10	0	1566953270000000	1566953270000000
\\x832ba7bf73d5b86429f3be7f245e0b8880f2e6feb29e6b3d6d5f13d586bf9fcc	payto://x-taler-bank/bank.test.taler.net/67	10	0	1566953055000000	1566953055000000
\\xd3ff34a089de9aec918e3b75a0178136171af9a84fbee676ea5a8cc2a947c060	payto://x-taler-bank/bank.test.taler.net/66	10	0	1566952736000000	1566952736000000
\\xe7fd68fd42067d407b98d1f30f80307353f5348047dc2649c82684240886e4fd	payto://x-taler-bank/bank.test.taler.net/65	10	0	1566952570000000	1566952570000000
\\xb65138b306c3a742753688438123087da53e07319fc30ddb769baec37780d204	payto://x-taler-bank/bank.test.taler.net/64	10	0	1566952542000000	1566952542000000
\\xf66b6fc40bfd70532fa6da42e8d746a20a74415647f99be6c5e5a855c97aa0a7	payto://x-taler-bank/bank.test.taler.net/63	10	0	1566952498000000	1566952498000000
\\x95a1d91c014ba399e5f7494c4135cb3c81b0f69eeed821c85da402fc07c9daac	payto://x-taler-bank/bank.test.taler.net/62	10	0	1566951959000000	1566951959000000
\\xcf622a2c3767c9f871100f9d782b792e1e6a5404833445d522789f924d169b4d	payto://x-taler-bank/bank.test.taler.net/61	10	0	1566951257000000	1566951257000000
\\x8d40f84bf39a8ca60e00d36825f2b156afaad70dff784f434ddfdb48682d53b6	payto://x-taler-bank/bank.test.taler.net/60	10	0	1566951247000000	1566951247000000
\\x5604e4942174f8ead3e75d576e38c5264e65757cc2a07c4e8ac1bf4da6b95b14	payto://x-taler-bank/bank.test.taler.net/59	10	0	1566950957000000	1566950957000000
\\x39a22bfce8e62bb9bf56113cc0272dc3c776cac1efa3c307d0fb84671d805d76	payto://x-taler-bank/bank.test.taler.net/58	10	0	1566950933000000	1566950933000000
\\xde8480cf26f349a625f9fcd83aa6498570479fad5c1193f9dda3f1ad683239db	payto://x-taler-bank/bank.test.taler.net/57	10	0	1566950662000000	1566950662000000
\\xb452f9eca6986c08f8c23a978e0f0be057a8ac79005640f87a993e16b95764fa	payto://x-taler-bank/bank.test.taler.net/56	10	0	1566949416000000	1566949416000000
\\x9f049ed6dbb886f85e6b62c86a9ce709d0d2de3abb8f6578d50233f88bc7f93d	payto://x-taler-bank/bank.test.taler.net/55	10	0	1566949255000000	1566949255000000
\\x4e7946826a660b06b17634fc4ead6f9ce8ca563ba56eb8e9569cbcec1a279ce8	payto://x-taler-bank/bank.test.taler.net/54	10	0	1566948664000000	1566948664000000
\\xf1c097c68600d04fd93be5c44fe7c67ee577d2c372eb981bf1889e669c1ee203	payto://x-taler-bank/bank.test.taler.net/53	10	0	1566948528000000	1566948528000000
\\xee80e518448d549e9319687310248ea6a8885dfa94ba0f78bf62a12c84825e9e	payto://x-taler-bank/bank.test.taler.net/52	10	0	1566948420000000	1566948420000000
\\x420480d63995c7c69bded84145ce20c13743f51cb83296d0b38713d4c3307dac	payto://x-taler-bank/bank.test.taler.net/51	10	0	1566947169000000	1566947169000000
\\x16dcd603b509d4829fc4f2c6ed34a7fc5d20be15dcd3c50248f97e609eedf3b1	payto://x-taler-bank/bank.test.taler.net/50	10	0	1566947161000000	1566947161000000
\\xc3109d60cc5a3adf527ad26fd6cb17223bcddf138cedd775ff8174a6b0d4d57f	payto://x-taler-bank/bank.test.taler.net/49	10	0	1566945900000000	1566945900000000
\\x285c1be3eddd195f60d19a0d35e7d9ac677db3414e3dbeb45a744740bf2ceade	payto://x-taler-bank/bank.test.taler.net/48	10	0	1566945799000000	1566945799000000
\\x38ab0a9f30c7bc5c524a634bd65ffa7d34fc8f1086531d20e69d055f5f6117c5	payto://x-taler-bank/bank.test.taler.net/47	10	0	1566939135000000	1566939135000000
\\x6ce4ed71b0493afa505c82bce3cf35fbb9ab1fbedd739d56de8fd0aeef256086	payto://x-taler-bank/bank.test.taler.net/46	10	0	1566939065000000	1566939065000000
\\xabf0b85b85cf80b41e0b39ab792ae7581b9855bfcf5e28d2a9a367476a84f754	payto://x-taler-bank/bank.test.taler.net/45	10	0	1566938932000000	1566938932000000
\\x5022184bf2d4433c31601ce1cbd91210cf746a47ea5e2986ccaafa8f44c73cb2	payto://x-taler-bank/bank.test.taler.net/44	10	0	1566810261000000	1566810261000000
\\x9a0403092f3d26c4f6e972e7790340048a3cd685cde9ea78564d8764434cdf9c	payto://x-taler-bank/bank.test.taler.net/43	10	0	1566810109000000	1566810109000000
\\xcc142afa684afbda15d34a034120d2e432ff922155baa4fe9c0ee650d0ff46cb	payto://x-taler-bank/bank.test.taler.net/42	10	0	1566809448000000	1566809448000000
\\xfc81c49fd4757e5ec657c9a2def34982bcbb006e9fe97021c0abeaf1734ec94a	payto://x-taler-bank/bank.test.taler.net/41	10	0	1566809376000000	1566809376000000
\\x897ae32910f7abed434f0610dd49237b33e444d0f8bd249430ca3dc95a10a2af	payto://x-taler-bank/bank.test.taler.net/40	10	0	1566807501000000	1566807501000000
\\xcc86e634723b519276a556ad6ad6b60f380f21b02032c0740ded5e35603bc478	payto://x-taler-bank/bank.test.taler.net/39	10	0	1566806872000000	1566806872000000
\\x90daeab4cbd5cb952510b3d199f3a0fefa8d45f77902390505db05bcfed8bf99	payto://x-taler-bank/bank.test.taler.net/38	10	0	1566806744000000	1566806744000000
\\xcd23da780b5f93611ac993fc63575d2bafacd46d2ca7a9397316ba08b70fcbb6	payto://x-taler-bank/bank.test.taler.net/37	10	0	1566806704000000	1566806704000000
\\x2155645ea096b73957f56c776e2e785db994dcec138fc4be4c41344322197551	payto://x-taler-bank/bank.test.taler.net/36	10	0	1566764816000000	1566764816000000
\\x7bcf85a0af25010d0df96e5826302329f4a0dba7056f7390c14e240916320a55	payto://x-taler-bank/bank.test.taler.net/35	10	0	1566764678000000	1566764678000000
\\x09c2c3d8d54d9183221a1afdee2873370eb17cb7ae6bbe259d1770a05082ec04	payto://x-taler-bank/bank.test.taler.net/34	10	0	1566764470000000	1566764470000000
\\x19d245eda964fadc2d68c0c1d05ee8ab761212dec72a0e151f670e9028cdf0b4	payto://x-taler-bank/bank.test.taler.net/33	10	0	1566764283000000	1566764283000000
\\xc2caebf149e241165f50e4b82c51e322f5bef5fd0c12dcf41f4ab597cf2d0919	payto://x-taler-bank/bank.test.taler.net/32	10	0	1566763196000000	1566763196000000
\\xb53d31ec78090b17be2ea17aedb42bf74a985215946d0674fa06c7c326fcaefe	payto://x-taler-bank/bank.test.taler.net/31	10	0	1566763185000000	1566763185000000
\\xdfcf3f95ec6a159fd971b8afc5203432523d38ca3fac1bd0dc11cee7c67d186b	payto://x-taler-bank/bank.test.taler.net/30	10	0	1566597556000000	1566597556000000
\\x3049fdf6ffd673a6711558e0b2cd34e53dbd3d0150407f12c896dd17056f80a9	payto://x-taler-bank/bank.test.taler.net/29	10	0	1566596474000000	1566596474000000
\\xd8457bd02eb1f93640e440d374168378a3a26810eaf6f462e0bb48ddf5fa25b1	payto://x-taler-bank/bank.test.taler.net/28	10	0	1566595257000000	1566595257000000
\\xac8df807cb36ef64846816ab0947cb59348b116f7cccb7fe378b486bcb06adbf	payto://x-taler-bank/bank.test.taler.net/27	10	0	1566594656000000	1566594656000000
\\x5350dea1916bd3d4324025fa70d64fcc7ca583520e6ca4ce3ce1b56f838e8bab	payto://x-taler-bank/bank.test.taler.net/26	10	0	1566594635000000	1566594635000000
\\x661e8a0a01acb4cbb4b3678b52e36cef107ecceb1bc34ae2c534a2105b6dbdba	payto://x-taler-bank/bank.test.taler.net/25	10	0	1566594212000000	1566594212000000
\\x1eea5a98a6944c6daa73ff98448f602b64f5a6008af7d5ec04e0948cd12521fd	payto://x-taler-bank/bank.test.taler.net/24	10	0	1566593124000000	1566593124000000
\\x9a76b3e571ceb844d248de54ef2edcc829a8e166da4cd0f4ee0ce1606fc49d67	payto://x-taler-bank/bank.test.taler.net/23	10	0	1566593002000000	1566593002000000
\\x4b640f53f10a01dba1998894b439df71831eff0fdaa4bf1e149a7399a879dfa7	payto://x-taler-bank/bank.test.taler.net/22	10	0	1566592884000000	1566592884000000
\\x18e56584f16f9f023708933014b179e9b810231b40217ecc257216ca139d6510	payto://x-taler-bank/bank.test.taler.net/21	10	0	1566592875000000	1566592875000000
\\x2d85cac3344b67052aeaaaeac0312e3bf3814781ae182d7b11e0fa6d7c301021	payto://x-taler-bank/bank.test.taler.net/20	10	0	1566592836000000	1566592836000000
\\xbe6c6cf37b37e4ac11f5efefffa16111e32ce79981d192ada976a329a30fda7e	payto://x-taler-bank/bank.test.taler.net/19	10	0	1566592711000000	1566592711000000
\\xc62f3c7a8cecd7c42d5ba2ef10932ec6d52d20e20d14a93107d5cfddfbdd8abb	payto://x-taler-bank/bank.test.taler.net/410	0	0	1568978646000000	1787311451000000
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
1	\\x39be3d8a13828b1e6ae16892eae29142123b844ef4c6d27f740c1b280b4a5332	\\x0000000000000370	10	0	payto://x-taler-bank/bank.test.taler.net/409	account-1	1566548112000000
2	\\x1ee905c938905bf754f7b3276222b1b3e5cc32b7e59118eac44dc7153b3987ed	\\x000000000000036d	10	0	payto://x-taler-bank/bank.test.taler.net/408	account-1	1566509997000000
3	\\x87cdd8e530911c8fb62d96252c353320ee10cc85faf2a16227ce3beaa46fafcc	\\x000000000000036b	10	0	payto://x-taler-bank/bank.test.taler.net/407	account-1	1566509747000000
4	\\x7b88ac2e47ea7d16069aa986e2b317ae174b3a863c42c63e15b0498efb469038	\\x0000000000000369	10	0	payto://x-taler-bank/bank.test.taler.net/406	account-1	1566509693000000
5	\\x0044d1b224b3a6eea5264bfeee1d11cd7d303f02728c0e75d66fbebe97d073ea	\\x0000000000000367	10	0	payto://x-taler-bank/bank.test.taler.net/405	account-1	1566509488000000
6	\\xa12e81176ea8dadbe50c63c1bf01757961d2e768e2f00dacbe7bccf5224deabe	\\x0000000000000365	10	0	payto://x-taler-bank/bank.test.taler.net/404	account-1	1566509398000000
7	\\xf2fb0d6aa54619644c92a7391e4b79db47017440ef88032ac7772d994f102e1c	\\x0000000000000363	10	0	payto://x-taler-bank/bank.test.taler.net/403	account-1	1566509355000000
8	\\x8b08b6956f045c42777b60aabef8f0c0a354409ccf970d00e4e55713c7943d48	\\x0000000000000361	10	0	payto://x-taler-bank/bank.test.taler.net/402	account-1	1566509253000000
9	\\xfa6afd2fc55db401ce4a8512bd58250452332b2663408e9ae10d15483effbeef	\\x000000000000035f	10	0	payto://x-taler-bank/bank.test.taler.net/401	account-1	1566491089000000
10	\\x822fb5586d2fb643b218593c820f074db3aec6bad1dc0cb76fe8f6154f174c99	\\x000000000000035d	10	0	payto://x-taler-bank/bank.test.taler.net/400	account-1	1566490545000000
11	\\xc135bc676a9f3b04a6702ba1882a57943e566e046158a0ca3ada7cf3f325b276	\\x000000000000035a	10	0	payto://x-taler-bank/bank.test.taler.net/399	account-1	1566481460000000
12	\\x02f7f50ac1f2d7d6b20c018f3d9357653eda9861c356f5a8bd6be0c501470468	\\x0000000000000358	10	0	payto://x-taler-bank/bank.test.taler.net/398	account-1	1566479139000000
13	\\x671ba24af73a74eddd46e524cd11f3741d141980038a3c9844d1187ce82bf463	\\x0000000000000356	10	0	payto://x-taler-bank/bank.test.taler.net/397	account-1	1566478898000000
14	\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	\\x0000000000000354	10	0	payto://x-taler-bank/bank.test.taler.net/396	account-1	1566476615000000
15	\\xe6dacd272de8282c0b32344101c61815e3921c4564cc346a991918b21904cedd	\\x0000000000000352	10	0	payto://x-taler-bank/bank.test.taler.net/395	account-1	1566476420000000
16	\\x66ec99ef569ba5b8262b5451943f743d82db4d46d850f56295229bc941e06d0c	\\x0000000000000350	10	0	payto://x-taler-bank/bank.test.taler.net/394	account-1	1566476135000000
17	\\x5a4622282f4ca44630980efeb12cbb2a8c3c46daa0d676186ccdad1103910954	\\x000000000000034e	10	0	payto://x-taler-bank/bank.test.taler.net/393	account-1	1566476014000000
18	\\x1c18ce673522c676d133d3fd38fc525c06f9139256f97733392aa476b38da935	\\x000000000000034c	10	0	payto://x-taler-bank/bank.test.taler.net/392	account-1	1566475277000000
19	\\x4d93a5159d2a5bd6910267a91c3111ac495329410097a1adcf772d3a240df2bb	\\x000000000000034a	10	0	payto://x-taler-bank/bank.test.taler.net/391	account-1	1566427028000000
20	\\xbd46bfe36609883ca276710aa7446bdf49d7a03f005472630e50a0784a53a741	\\x0000000000000348	10	0	payto://x-taler-bank/bank.test.taler.net/390	account-1	1566427006000000
21	\\x2dbb53c2f3627f50b18ec54e15246c7b5f81a15683f53a7177029814f8da8bc2	\\x0000000000000345	10	0	payto://x-taler-bank/bank.test.taler.net/389	account-1	1566405376000000
22	\\x1f4681908ed2f225632346cc1e3b4988ce8fa6c1c8ab179f978b3bcff3c21bf1	\\x0000000000000343	10	0	payto://x-taler-bank/bank.test.taler.net/388	account-1	1566405026000000
23	\\x688b922cfa19931ba3d9030b747bdc2da9716aac4e53f21a15c5988456915581	\\x0000000000000341	10	0	payto://x-taler-bank/bank.test.taler.net/387	account-1	1566404945000000
24	\\x012e41df79ff63a8f39d2817a86bbc0e60f14e70440fbab3c234fc4a8d05d439	\\x000000000000033e	10	0	payto://x-taler-bank/bank.test.taler.net/386	account-1	1566397498000000
25	\\x6c3a52338741d0f462f571f42daf5be81b7a945da9ad871cc9f58ddd700193aa	\\x000000000000033b	10	0	payto://x-taler-bank/bank.test.taler.net/385	account-1	1566394252000000
26	\\xc8e442c5c85ef054a27974ba39c3745c9d017f4bf8e52768c5e8669ba8583e66	\\x0000000000000339	10	0	payto://x-taler-bank/bank.test.taler.net/384	account-1	1566394222000000
27	\\xc9675953172121e16dab952fc11a250245a5682fc6c5cb921cbe1753869d3299	\\x0000000000000337	10	0	payto://x-taler-bank/bank.test.taler.net/383	account-1	1566393958000000
28	\\xc37168aec489a6472db4efc0a85feeb19f6c8cdf1de3723945bba9bd8a7fb634	\\x0000000000000335	10	0	payto://x-taler-bank/bank.test.taler.net/382	account-1	1566393343000000
29	\\x0a26d1acfe138d947700857a157a007c0f8b44cb2cd5387c4e4ba1dc21603e6c	\\x0000000000000333	10	0	payto://x-taler-bank/bank.test.taler.net/381	account-1	1566393317000000
30	\\xc7624530ea124cca7e8661163d6b4016d2a4252b63c901a77a9d1771245da8f9	\\x0000000000000331	10	0	payto://x-taler-bank/bank.test.taler.net/380	account-1	1566392677000000
31	\\xb71c07fdff675806af9e20022b7bf5ec0ec16f0892d3b866436f659da502a25f	\\x000000000000032f	10	0	payto://x-taler-bank/bank.test.taler.net/379	account-1	1566392545000000
32	\\xc8f38a375831272de806e769f96d6c4c142b9c249a5110eb26c35117f69014a3	\\x000000000000032d	10	0	payto://x-taler-bank/bank.test.taler.net/378	account-1	1566389252000000
33	\\xe67cf6c190418a44ff772b5af0075de9f50ecb27d168c907837528575531a747	\\x000000000000032b	10	0	payto://x-taler-bank/bank.test.taler.net/377	account-1	1566389178000000
34	\\x74a4f75e0092c7f48bacfcdc2b3eac5fa93c61548b0bdd053e0bfbb741d9af51	\\x0000000000000325	10	0	payto://x-taler-bank/bank.test.taler.net/376	account-1	1566387148000000
35	\\x62ce130deab667ded5da342d4a7c8a48259c5464e4c11f9a41a155622f736d8a	\\x0000000000000321	10	0	payto://x-taler-bank/bank.test.taler.net/375	account-1	1566386814000000
36	\\x53339a2bc10f6d6dc9f3c275269fab85e67ea25dc2853d5c25898ed41d51331e	\\x000000000000031c	10	0	payto://x-taler-bank/bank.test.taler.net/374	account-1	1566386362000000
37	\\xb2f0675021b8b2b2c82a33d7de06a6188014ef6f641ec1f63b98574adc4a5a79	\\x0000000000000319	10	0	payto://x-taler-bank/bank.test.taler.net/373	account-1	1566386271000000
38	\\x64de8ad09221295cda8823d29797b5335c3c40efd0111a20134fef96bbd9ac9a	\\x0000000000000317	10	0	payto://x-taler-bank/bank.test.taler.net/372	account-1	1566386085000000
39	\\x7140831bef79c6208bca40a3b926a8045cc19cd504f0502261d8d8c5872c9de9	\\x0000000000000314	10	0	payto://x-taler-bank/bank.test.taler.net/371	account-1	1566385895000000
40	\\xe3c38f7f9a1f808655c624f450bd9e1d084ac6448d9f42fbe56dc99c017b176e	\\x0000000000000311	10	0	payto://x-taler-bank/bank.test.taler.net/370	account-1	1566385833000000
41	\\xfc13820602150f5b065d5e8c34ad9c01b28403af35f155bf471c478399382725	\\x000000000000030e	10	0	payto://x-taler-bank/bank.test.taler.net/369	account-1	1566376892000000
42	\\x5d7b8eea903cbe3c4926db1c8c8cce69482ecbc196bd65813388ce3237d77f56	\\x000000000000030c	10	0	payto://x-taler-bank/bank.test.taler.net/368	account-1	1566376792000000
43	\\x77e1ae7a8bfaadc974396088d2fd22fee5398df641a7c3dba0760765875cf6b5	\\x000000000000030a	10	0	payto://x-taler-bank/bank.test.taler.net/367	account-1	1566373449000000
44	\\xdd6e5ecaad109e27520aacc88c39cc4830235f280e8bd11779f38ebee15b237f	\\x0000000000000307	10	0	payto://x-taler-bank/bank.test.taler.net/366	account-1	1566333832000000
45	\\xc856b9453e72fc92eeecf9614cba6acfdfb67a39d1f1017b59803ec0f8f5f8ad	\\x0000000000000305	10	0	payto://x-taler-bank/bank.test.taler.net/365	account-1	1566333792000000
46	\\x119efdc91109466f9d6c8bcf33f956d0046b01380ce66b44ebc3a2902d827d89	\\x0000000000000303	10	0	payto://x-taler-bank/bank.test.taler.net/364	account-1	1566333684000000
47	\\x38cc57b994cf977e00c6c4c25357796e9c2d79b44ce890ce49925cdc6c3d54ac	\\x0000000000000301	10	0	payto://x-taler-bank/bank.test.taler.net/363	account-1	1566332441000000
48	\\x0f352c26485d153ab1654b49a06dc5a47a0b4a14bf4a42cb4cbd18b87fb07374	\\x00000000000002ff	10	0	payto://x-taler-bank/bank.test.taler.net/362	account-1	1566331804000000
49	\\xa2f9f8326db9d373b252fcc3a0401bc85b3e97618dc3a432487ef38cd9a6517a	\\x00000000000002fc	10	0	payto://x-taler-bank/bank.test.taler.net/361	account-1	1566330461000000
50	\\x46e452f1184d8f6d218534b68b79b8cf6143f1ebaf118a9773546aa200996955	\\x00000000000002f9	10	0	payto://x-taler-bank/bank.test.taler.net/360	account-1	1566330320000000
51	\\x47dbd1fbb39cee3d39c117e376c472fa0d0fc6fceccd5f5e978bace5a6af0ab0	\\x00000000000002f6	10	0	payto://x-taler-bank/bank.test.taler.net/359	account-1	1566330086000000
52	\\x5941c4d722de161c804086ea30952008b7dd1a6aaf10ef708e2fa122102bae7b	\\x00000000000002f3	10	0	payto://x-taler-bank/bank.test.taler.net/358	account-1	1566329229000000
53	\\x051cbec08070f5a75e6de51d35e1aeb7b01a36036a141d2066181092d1d39b11	\\x00000000000002f1	10	0	payto://x-taler-bank/bank.test.taler.net/357	account-1	1566328595000000
54	\\x69cff834caa39abbb70820d036158ce6cd3a7f99cb8cec263337660b7383bcee	\\x00000000000002ec	10	0	payto://x-taler-bank/bank.test.taler.net/356	account-1	1566326490000000
55	\\x6874b7482af6d0ad81a6d31e6fd08c7ab18503c28e053bda598bfd0acb180c7e	\\x00000000000002e9	10	0	payto://x-taler-bank/bank.test.taler.net/355	account-1	1566326185000000
56	\\xdeaaddb0ca6611d9ed384e3b729028fcc22d2fa5764e3843aad3172958ef79d3	\\x00000000000002e7	10	0	payto://x-taler-bank/bank.test.taler.net/354	account-1	1566325818000000
57	\\xcbeb4efeee8f755ad46a4cbbe367284d0a31e8355b703eaf3c62a90c25bb6815	\\x00000000000002e4	10	0	payto://x-taler-bank/bank.test.taler.net/353	account-1	1566320369000000
58	\\xa044250c7644a8664c2d7dd4f4146946c7d7a74cc9d3c72f24861cca285e515e	\\x00000000000002e0	10	0	payto://x-taler-bank/bank.test.taler.net/352	account-1	1566316221000000
59	\\x9ad482c0b94c3fe5403c0093d5609a77e459422795cc0ad7b091f6a28039c281	\\x00000000000002de	10	0	payto://x-taler-bank/bank.test.taler.net/351	account-1	1566316062000000
60	\\x06f725b34ff44ea72a88e0d72d9c754462176850b63841e5ac62eeaa0107da8e	\\x00000000000002da	10	0	payto://x-taler-bank/bank.test.taler.net/350	account-1	1566313444000000
61	\\x4aba78fd0c360bd6bdfb1be8c0033adc09d669e7363ff4f75c7addbead866087	\\x00000000000002d8	10	0	payto://x-taler-bank/bank.test.taler.net/349	account-1	1566312135000000
62	\\x003756a82312c1f165d22735a4d91a0931970335d69739be893422b3630bd5df	\\x00000000000002d6	10	0	payto://x-taler-bank/bank.test.taler.net/348	account-1	1566312049000000
63	\\x7274923e113464192d274534a3b8dd38572393cf8b6b9a26973ce0c657f830fd	\\x00000000000002d4	10	0	payto://x-taler-bank/bank.test.taler.net/347	account-1	1566300097000000
64	\\xb353ec37ab0e6c7b624ae1779404f65f4b7c3dc601a72ca2e0d7f23633946144	\\x00000000000002d2	10	0	payto://x-taler-bank/bank.test.taler.net/346	account-1	1566300079000000
65	\\xf6157d960f7b08f4ecd45e8f856090fcb22e069858394a4e7fc97488a88852a5	\\x00000000000002d0	10	0	payto://x-taler-bank/bank.test.taler.net/345	account-1	1566300069000000
66	\\x14a56bea0d1606f7636eb8ddcbbfcd8a9479130b22589f154e37ee1575842e1e	\\x00000000000002ce	10	0	payto://x-taler-bank/bank.test.taler.net/344	account-1	1566297956000000
67	\\x3eceb3f3a13e966853b828a49921188a0305ccfc88be178f2a76a7e210f174ec	\\x00000000000002cc	10	0	payto://x-taler-bank/bank.test.taler.net/343	account-1	1566297947000000
68	\\xf939b9ad110e76af9ee82c5924c812709f610e73f651a120b7b93a35ad8a9462	\\x00000000000002ca	10	0	payto://x-taler-bank/bank.test.taler.net/342	account-1	1566297933000000
69	\\xfefdc664b156a8956c22392708056f7771beb50eef224383e7be4e7178a6a8bb	\\x00000000000002c8	10	0	payto://x-taler-bank/bank.test.taler.net/341	account-1	1566297922000000
70	\\x0e2d0beab43b0b4fd20157e8b373f21b1fee2a513ebe0fcd18464bfe22889272	\\x00000000000002c6	10	0	payto://x-taler-bank/bank.test.taler.net/340	account-1	1566297730000000
71	\\x0425ba60520bbc67ea59dd44fdac94d44aec328d4a504f9a96cd7115d2d7718b	\\x00000000000002c4	10	0	payto://x-taler-bank/bank.test.taler.net/339	account-1	1566297601000000
72	\\x6e9d183ab868e7ff9d40138dd763896cb8ee9b230e2de94f73b0d788b738f8a4	\\x00000000000002c2	10	0	payto://x-taler-bank/bank.test.taler.net/338	account-1	1566245473000000
73	\\x813db9bd108f103f010eee5c9347a0f8d36da0076ecdfc2aef7e02d643234196	\\x00000000000002c1	10	0	payto://x-taler-bank/bank.test.taler.net/337	account-1	1566245473000000
74	\\x59c56af7431f2115a0c22aa89892d170a9a9471db5014e8a824fbc19dcc2d843	\\x00000000000002c0	10	0	payto://x-taler-bank/bank.test.taler.net/335	account-1	1566245473000000
75	\\x53d4ea53beca2041bb9b7885f1bf52fbac6b87c44ee7c27b8d5e9eb6d17cc0e5	\\x00000000000002bf	10	0	payto://x-taler-bank/bank.test.taler.net/336	account-1	1566245473000000
76	\\xfe59643d79bcc5ecf39a4fda8016c47fd7c8c3635f1bba0a7f6e0c13c134a4b8	\\x00000000000002be	10	0	payto://x-taler-bank/bank.test.taler.net/334	account-1	1566245472000000
77	\\xccc34040dbcf81f0f68cf8c23a5c381c48a8819bf7f0f2d83b24c409023361e6	\\x00000000000002b8	10	0	payto://x-taler-bank/bank.test.taler.net/333	account-1	1566245061000000
78	\\x9abf75e6216b8039d914aa14b8c6ef77952b49f8f4b25cc29ee0a6e0cacbfc70	\\x00000000000002b6	10	0	payto://x-taler-bank/bank.test.taler.net/332	account-1	1566245006000000
79	\\x76c21837710c2e390b9fe23674f581e87e07ce96e4972c1af82ec1a0847ae95d	\\x00000000000002b4	10	0	payto://x-taler-bank/bank.test.taler.net/331	account-1	1566244957000000
80	\\xc725d349c67fd479c2c512e29e33055753da64877d33335fb1b2432e7a32d999	\\x00000000000002b2	10	0	payto://x-taler-bank/bank.test.taler.net/330	account-1	1566244950000000
81	\\x2af399b74d0691fb36c2e2b6c00631694b51607c332fd97f29a8d4ecca5c7ef6	\\x00000000000002b0	10	0	payto://x-taler-bank/bank.test.taler.net/329	account-1	1566244024000000
82	\\xd58aa182bdc6b8f4463bf392e0bb003325bfb653ad7c18f32d39e38fd20e7ed0	\\x00000000000002ae	10	0	payto://x-taler-bank/bank.test.taler.net/328	account-1	1566243569000000
83	\\xe7ac2051b945e977cdb2a613d4434c04c26dd3b102a1bc82d29d08a81ae86b2b	\\x00000000000002ac	10	0	payto://x-taler-bank/bank.test.taler.net/327	account-1	1566243539000000
84	\\x2f45b07e937fd0a1feb3d9fcc7aa6c149a96e84338fa251f53f148ceca4b96d5	\\x00000000000002aa	10	0	payto://x-taler-bank/bank.test.taler.net/326	account-1	1566243321000000
85	\\x204f1f80cd9e66810bbf74e58cb1838d904ee5941ed205aba33bf9f1e236e49d	\\x00000000000002a8	10	0	payto://x-taler-bank/bank.test.taler.net/325	account-1	1566243309000000
86	\\xdb41e9f1ad98bb9bf42c952b770c69c4019fa6c4524f77f92cb4189e96bca115	\\x00000000000002a6	10	0	payto://x-taler-bank/bank.test.taler.net/324	account-1	1566242800000000
87	\\x30fba371e70b4ebc0a40f952c43d50d18719b36d310b891059808ea5a21c3710	\\x00000000000002a4	10	0	payto://x-taler-bank/bank.test.taler.net/323	account-1	1566242788000000
88	\\x26bd0786ce312f0aec4cc46d8c2a0368974f065f61ecc345c713aa0fc8fa5c2a	\\x00000000000002a2	10	0	payto://x-taler-bank/bank.test.taler.net/322	account-1	1566242772000000
89	\\x3e6809817ca4477f5ec4ac74c0bbb76e48448176043a2cb456b0dc455a79632f	\\x00000000000002a0	10	0	payto://x-taler-bank/bank.test.taler.net/321	account-1	1566242748000000
90	\\x5a374956e5ff8785db62f4deccdc41d65aad3bb1927344122447acc016aa44f9	\\x000000000000029e	10	0	payto://x-taler-bank/bank.test.taler.net/320	account-1	1566242656000000
91	\\xc3c6006069c05603856ac9e6bf25192f6684467721b96350bdfabc8008bbec9d	\\x000000000000029c	10	0	payto://x-taler-bank/bank.test.taler.net/319	account-1	1566242538000000
92	\\xa5d0664f9f0fdfb4407c6e90712d57e98e824dc1bbc75c79620f68f97d8fd5ca	\\x000000000000029a	10	0	payto://x-taler-bank/bank.test.taler.net/318	account-1	1566242396000000
93	\\x7039453d2727338652a5432ffca59220fe15ebb3e09399d238215311f015107d	\\x0000000000000298	10	0	payto://x-taler-bank/bank.test.taler.net/317	account-1	1566242338000000
94	\\x3428bcdcd2725e6038bba0d5e3189f3caf0c342d55a25d02be539d6ab97cc20c	\\x0000000000000296	10	0	payto://x-taler-bank/bank.test.taler.net/316	account-1	1566241294000000
95	\\x22c98e04feee74f42fba4ab3f00627a118c4d8279df397776bb785903e07ab1e	\\x0000000000000294	10	0	payto://x-taler-bank/bank.test.taler.net/315	account-1	1566240636000000
96	\\x59998f08f6e8f35ea10c51c5700aae79b9f6d6b5f684a377a7f5b2fa6a64a269	\\x0000000000000292	10	0	payto://x-taler-bank/bank.test.taler.net/314	account-1	1566240236000000
97	\\x10dd95f3a5de768b7690839be29f2d8974b0654d13f20b5f7437d768d14f51bc	\\x0000000000000290	10	0	payto://x-taler-bank/bank.test.taler.net/313	account-1	1566240159000000
98	\\x87a6b79a88d73b92f7169010d401421224a6a24b67f40471c4a4761cc0f0bfb2	\\x000000000000028e	10	0	payto://x-taler-bank/bank.test.taler.net/312	account-1	1566240037000000
99	\\x33396f85d648a84af67f09d35532751fa8d90e22b218d0798bd444b12ddac3a2	\\x000000000000028c	10	0	payto://x-taler-bank/bank.test.taler.net/311	account-1	1566239308000000
100	\\x91837011a5b129b2a1ecdaf92cf0fe157479e26044f16705f06aab77c7157879	\\x000000000000028a	10	0	payto://x-taler-bank/bank.test.taler.net/310	account-1	1566239253000000
101	\\x789a55c8a99464a9a7c9c3640e917aa0b4ee760cd49850b1c2c0173480e1486d	\\x0000000000000288	10	0	payto://x-taler-bank/bank.test.taler.net/309	account-1	1566239010000000
102	\\xed4538ca12e87d07f8a036054059c92f875b1fdf5f5cbe12a0dd8c72efc0ef1b	\\x0000000000000286	10	0	payto://x-taler-bank/bank.test.taler.net/308	account-1	1566238980000000
103	\\x1c524fbbb8045eaff17a3935d67f85234f342c943933fb1a0e827f99330bcf05	\\x0000000000000284	10	0	payto://x-taler-bank/bank.test.taler.net/307	account-1	1566238913000000
104	\\x29bb82bedb668a22791007266113a81977b54d9524bfb195812eb4637f449d1d	\\x0000000000000282	10	0	payto://x-taler-bank/bank.test.taler.net/306	account-1	1566238897000000
105	\\xcd9a6ca7e8cf43aabcf1b7e3403139c2ac1d990f78334360d326660ceec8df15	\\x0000000000000280	10	0	payto://x-taler-bank/bank.test.taler.net/305	account-1	1566238783000000
106	\\xbaf74548c792dea461ca5aaf83a69b3a7c9c220a910ab45c286a1ae7df7f1d77	\\x000000000000027e	10	0	payto://x-taler-bank/bank.test.taler.net/304	account-1	1566238056000000
107	\\x7e63f67c1940a9b23d13697aa6582a1fe69581bbd2f1c5098cd3561a989eba3a	\\x000000000000027c	10	0	payto://x-taler-bank/bank.test.taler.net/303	account-1	1566236519000000
108	\\x59bfd4e6dbaa2dfdb58244208e88533a7849ceb3e3e235e427d516ccd69ac5fc	\\x000000000000027a	10	0	payto://x-taler-bank/bank.test.taler.net/302	account-1	1566236071000000
109	\\x268c99db0a689c8fe3544e83745f2c5e3d476ae6e6abe8b62babdcdc62208ee1	\\x0000000000000278	10	0	payto://x-taler-bank/bank.test.taler.net/301	account-1	1566232865000000
110	\\xe7e3ffe3752203bbfa38003e5c6ea51c395c2aa4056b258461f0b24dfbc5a773	\\x0000000000000276	10	0	payto://x-taler-bank/bank.test.taler.net/300	account-1	1566232802000000
111	\\x3b34626e4bd1d6a90a17685dffa13b1de5eaaaefee9dff5b62531b6f9c2b25cb	\\x0000000000000274	10	0	payto://x-taler-bank/bank.test.taler.net/299	account-1	1566232151000000
112	\\x1c50880a086245f96b09dbc9262696d31570b359e9aa847c62dc724e1bbc3904	\\x0000000000000272	10	0	payto://x-taler-bank/bank.test.taler.net/298	account-1	1566212292000000
113	\\xe532b4eaa3a651af35fe482844cf4ee58d9933594e1d07348db46d507d44d136	\\x0000000000000270	10	0	payto://x-taler-bank/bank.test.taler.net/297	account-1	1566211792000000
114	\\xa9508cf654f874b6ac7c137c67a34daadd7566c01452359b0c1974fd866c88a9	\\x000000000000026d	10	0	payto://x-taler-bank/bank.test.taler.net/296	account-1	1566162797000000
115	\\xb6dd4e754c04f7f454fc76eeea421a02db0ab80cadd6e095913aa6a467d08df8	\\x000000000000026a	10	0	payto://x-taler-bank/bank.test.taler.net/295	account-1	1566162322000000
116	\\xc484befd64ce803855834b06e849343331d654f98d2c681c28ae2547533afb07	\\x0000000000000266	10	0	payto://x-taler-bank/bank.test.taler.net/294	account-1	1566162199000000
117	\\x9222bf7c3c95fb9eda6f228d44573407bfbd4c440351830f2d770ac84ab44e36	\\x0000000000000264	10	0	payto://x-taler-bank/bank.test.taler.net/293	account-1	1566162183000000
118	\\x9c377c7a5181ac3a9cd7609eea358428156380615afc3730f87bee265213a756	\\x0000000000000261	10	0	payto://x-taler-bank/bank.test.taler.net/292	account-1	1566161708000000
119	\\xb800e06c8b550082d031a22fde02d8654c27fc7e778c33ab8296349365f72347	\\x000000000000025f	10	0	payto://x-taler-bank/bank.test.taler.net/291	account-1	1566161657000000
120	\\xe57325eea480ac0c9b3434a30b1952ba7deac6d00106b6b9974878edcdf40e7e	\\x000000000000025c	10	0	payto://x-taler-bank/bank.test.taler.net/290	account-1	1566161534000000
121	\\x406b9add395d06468c5828d686b1e78e58f7b6972a25201f452626a4f7dd7d7a	\\x000000000000025a	10	0	payto://x-taler-bank/bank.test.taler.net/289	account-1	1566161473000000
122	\\x89470dee4c3110f9cdc4b7f851b003d1de5417379f473bbdb57454e1997c0a0c	\\x0000000000000256	10	0	payto://x-taler-bank/bank.test.taler.net/287	account-1	1566161289000000
123	\\xda46933e2a492f1c30d56d18176082a5bfb1b9b073abd0cce747f5111137a8b1	\\x0000000000000253	10	0	payto://x-taler-bank/bank.test.taler.net/286	account-1	1566161223000000
124	\\x4c7d9dde23ca42d415f01730f0b19c4ac60560c40095652048b08d2633aa2810	\\x0000000000000251	10	0	payto://x-taler-bank/bank.test.taler.net/285	account-1	1566161205000000
125	\\x5e293aeb6c08a5bcbb1e61df798220451f07f36d00affaa9190775a5f7180caa	\\x000000000000024f	10	0	payto://x-taler-bank/bank.test.taler.net/284	account-1	1566160855000000
126	\\xefe525ec2968cd6845b8c92b02a73c0a0af9af88de003d82ca12deb9e22e9dc0	\\x000000000000024d	10	0	payto://x-taler-bank/bank.test.taler.net/283	account-1	1566160503000000
127	\\xaa87f84bcc4744d63b96cff8436a5f88405dfb5f22a39fd9f9552e8633de9942	\\x000000000000024b	10	0	payto://x-taler-bank/bank.test.taler.net/282	account-1	1566160323000000
128	\\x6ded4375cd71b389104b9096226a89fa1a1846cb7af324842e4a62ca4f32072d	\\x0000000000000249	10	0	payto://x-taler-bank/bank.test.taler.net/281	account-1	1566160271000000
129	\\x1b0e3b898562b405d5989b3617178871f6a0e73f1ca2ade7c293ed29ad760c72	\\x0000000000000246	10	0	payto://x-taler-bank/bank.test.taler.net/280	account-1	1566159278000000
130	\\xd7a6cb733790839a79bed1e9d2ee4b7d8fd66ae70f1645c84edbc535b0d77e33	\\x0000000000000244	10	0	payto://x-taler-bank/bank.test.taler.net/279	account-1	1566159163000000
131	\\xad658d529cb575c0d1d025056f724ad59c2f0efadfc052d4300d4066669f5f20	\\x0000000000000242	10	0	payto://x-taler-bank/bank.test.taler.net/278	account-1	1566157690000000
132	\\xe0b3f02bf670cd068c2483b252c2a47ca204d46b6821ea94f58444345d2004c7	\\x000000000000023f	10	0	payto://x-taler-bank/bank.test.taler.net/277	account-1	1566152613000000
133	\\x66af8e219c20e49afe73128b8687a39e0b8a36f6ce79286714c058e0efdd9669	\\x000000000000023d	10	0	payto://x-taler-bank/bank.test.taler.net/276	account-1	1566152522000000
134	\\x7a218bdf8b9e773794613b3db323fcc95867819c59e24726f7dcf4a13be842d9	\\x000000000000023b	10	0	payto://x-taler-bank/bank.test.taler.net/275	account-1	1566150042000000
135	\\x33453afe5db166f0aa10e4acda686dba022990a845753f3d6d06a61b24cd46a5	\\x0000000000000239	10	0	payto://x-taler-bank/bank.test.taler.net/274	account-1	1566149967000000
136	\\x6b7cede5ceb81248262a13b1d86f2d3b392c18e0c93788fecb5284917523a57d	\\x0000000000000237	10	0	payto://x-taler-bank/bank.test.taler.net/273	account-1	1566149930000000
137	\\xb9d4fdfed4243cf830cebc3195b0d2659649d8a8b4aa885301f83410ae0024e4	\\x0000000000000234	10	0	payto://x-taler-bank/bank.test.taler.net/271	account-1	1566149859000000
138	\\xd5da4a1a66b10dc4e12ab7461fe65023ee0ab2bacbef8fff13a0c0a1de15b66d	\\x0000000000000231	10	0	payto://x-taler-bank/bank.test.taler.net/270	account-1	1566138861000000
139	\\x3af59e0132735e05e27b112d6392ee58a11489cf568bbb5c25bb595405521ff3	\\x000000000000022e	10	0	payto://x-taler-bank/bank.test.taler.net/269	account-1	1566138687000000
140	\\x469bf9c86abb396de1863568f5789599dc6a439450f3f1905f6212bad9f4df9a	\\x000000000000022b	10	0	payto://x-taler-bank/bank.test.taler.net/268	account-1	1566138565000000
141	\\xa5b58e2c15151cc21b2a6d64a01f9358d6c0850067a34f9162351ecac4a57222	\\x0000000000000228	10	0	payto://x-taler-bank/bank.test.taler.net/267	account-1	1566138394000000
142	\\x271ee8933b0258c5551dcdc999da5b708b36ed97dad53800c45bc72d49a39cd7	\\x0000000000000225	10	0	payto://x-taler-bank/bank.test.taler.net/266	account-1	1566138213000000
143	\\x0ccff4d54e80cb3dd68f6e916973508e77051caaae735dd03bc306cfe0afae74	\\x0000000000000222	10	0	payto://x-taler-bank/bank.test.taler.net/265	account-1	1566138073000000
144	\\x6363234157eab234dc540d977e06cf6681bae43e7d2d87beed4739c08f6377c6	\\x000000000000021f	10	0	payto://x-taler-bank/bank.test.taler.net/264	account-1	1566137941000000
145	\\x294eb33578c0dd1135de2b6cc411cd59881a9add9f786995118673899e9c3e87	\\x000000000000021c	10	0	payto://x-taler-bank/bank.test.taler.net/263	account-1	1566137744000000
146	\\xa9d62c09b31f66606af346d0c7e64f77a92954a999e50ffcf574a217e8cb31e4	\\x0000000000000219	10	0	payto://x-taler-bank/bank.test.taler.net/262	account-1	1566137374000000
147	\\xe4d05ad2b0b5e27f3695806e468d54592cd5405e281485196ffa234e63fc68cb	\\x0000000000000216	10	0	payto://x-taler-bank/bank.test.taler.net/261	account-1	1566137157000000
148	\\xf0fda0cd3dda1d31a598c5b9e850a7c54456f8c482af6c1f70b380fd3a659c46	\\x0000000000000213	10	0	payto://x-taler-bank/bank.test.taler.net/260	account-1	1566136948000000
149	\\x695a2de3e0bfdee784b2409b58d18e069f55768745622205a4cb2a99016d976e	\\x0000000000000210	10	0	payto://x-taler-bank/bank.test.taler.net/259	account-1	1566136833000000
150	\\x59ba84ccb16e2a8c0197ae704c9805452d9f91203f0e2a2414865fb43b11b60d	\\x000000000000020d	10	0	payto://x-taler-bank/bank.test.taler.net/258	account-1	1566136582000000
151	\\xf7afb294f813be7682bda81a109f8cebc21c7dde782f897359ce3c4503a915f3	\\x000000000000020a	10	0	payto://x-taler-bank/bank.test.taler.net/257	account-1	1566135337000000
152	\\xa242dcf952f7a0284907e66479db7510f74fff91ce0c318c69e30cc42ac22b28	\\x0000000000000207	10	0	payto://x-taler-bank/bank.test.taler.net/256	account-1	1566135008000000
153	\\xa46479979b59dac9665291fe8c99f56fafd020ab6378518b24a7de4162c0a8fe	\\x0000000000000204	10	0	payto://x-taler-bank/bank.test.taler.net/255	account-1	1566133668000000
154	\\x9307406b793081d213b291e1220b05afa8f8dbe8f0a297729a78228d7b4f5363	\\x0000000000000202	10	0	payto://x-taler-bank/bank.test.taler.net/254	account-1	1566133653000000
155	\\x935c559fcf339b66ea197098e4a7165a373cada72ce6326c6649f21bb2b6958a	\\x00000000000001fe	10	0	payto://x-taler-bank/bank.test.taler.net/252	account-1	1566062283000000
156	\\x44884e596728d1764a441c476b6d1600f4e172b82224579a7a9c96d0264db3f3	\\x00000000000001fb	10	0	payto://x-taler-bank/bank.test.taler.net/251	account-1	1566061181000000
157	\\xa47e3ec298a912ce770d6f76505ab6bad3bc4f43012ea0a7d02018359ced5e77	\\x00000000000001f6	10	0	payto://x-taler-bank/bank.test.taler.net/247	account-1	1566060055000000
158	\\xec426b2ba4cd2036d645ace13c17ec24d034c47123f9b7259b19bddd75bbc282	\\x00000000000001f4	10	0	payto://x-taler-bank/bank.test.taler.net/246	account-1	1566060049000000
159	\\xfa6430afd028e2230004a93f5f989f716b04f07f22075c0f71f0de7fb885556d	\\x00000000000001f2	10	0	payto://x-taler-bank/bank.test.taler.net/245	account-1	1566060036000000
160	\\x59d46300018a3020106c7635630a580763c94359e41bb30381a5234ffb259462	\\x00000000000001ef	10	0	payto://x-taler-bank/bank.test.taler.net/243	account-1	1566049629000000
161	\\x3735705df5fdb4391e2c7308b6efd8aefb2cd17feed80c7d7409b062c4a7020b	\\x00000000000001ec	10	0	payto://x-taler-bank/bank.test.taler.net/241	account-1	1566049589000000
162	\\xb7c7fa0443475b8a8f7612bfeb862c3e27c75ef08c2ed9f4ee524e95ba215155	\\x00000000000001ea	10	0	payto://x-taler-bank/bank.test.taler.net/240	account-1	1566048975000000
163	\\xe5021623374e4f73a1021b432393316a64b9ff7d8a55b08fa4889bc3ea14cd5a	\\x00000000000001e8	10	0	payto://x-taler-bank/bank.test.taler.net/239	account-1	1566044441000000
164	\\x9c9aee06fecf3caa3de9173ae0afb78a3df2361f4a1c98bbaa2fa124dc774d3b	\\x00000000000001e6	10	0	payto://x-taler-bank/bank.test.taler.net/238	account-1	1565999485000000
165	\\x0f44803fb16fff27d5b00d0ff093c089dc7671feef732783d98b6057c78795ee	\\x00000000000001e4	10	0	payto://x-taler-bank/bank.test.taler.net/237	account-1	1565999477000000
166	\\xcb5d2f41dae0505e076d87da9c209b574708290b94ee53eb7c58b719ff9f8e4c	\\x00000000000001e2	10	0	payto://x-taler-bank/bank.test.taler.net/236	account-1	1565999460000000
167	\\xd66e178d92b2c62fec79634fb20a21c5700507111b36bde3a838a9e6afdcd962	\\x00000000000001e0	10	0	payto://x-taler-bank/bank.test.taler.net/235	account-1	1565999360000000
168	\\xd0afe6a042bd0d72502690e9b60cc521f101fe75eb854595e3679b3ff1d1f913	\\x00000000000001de	10	0	payto://x-taler-bank/bank.test.taler.net/234	account-1	1565999354000000
169	\\x5180d87442313b7237f1be51fb363524f197ee48e304d04b33f4f46aec114410	\\x00000000000001dc	10	0	payto://x-taler-bank/bank.test.taler.net/233	account-1	1565999301000000
170	\\x6189f786c04b5e735b639da1779c9806f86c4dd9324d92cb9ef9dbc6fc515b7b	\\x00000000000001da	10	0	payto://x-taler-bank/bank.test.taler.net/232	account-1	1565999283000000
171	\\x866ec7f2b2123ead9e3500c0ff1f83e386f392c49e2f163ffe697ffd41e0f90d	\\x00000000000001d8	10	0	payto://x-taler-bank/bank.test.taler.net/231	account-1	1565999276000000
172	\\x99ecea1c2119254d96d98ef43424b4cbe314fb5bb440e838f6a8a140301bce6d	\\x00000000000001d6	10	0	payto://x-taler-bank/bank.test.taler.net/230	account-1	1565998955000000
173	\\x99fbc0d1d5729fd3f0b33736844196fff3d8d278053a60b9b27b47916c3ddd0d	\\x00000000000001d4	10	0	payto://x-taler-bank/bank.test.taler.net/229	account-1	1565998910000000
174	\\x5a385ed4779a13d58684098b70882788437bab11102b38ad277aef41baada706	\\x00000000000001d2	10	0	payto://x-taler-bank/bank.test.taler.net/228	account-1	1565998663000000
175	\\xb52d325f032b2791d504a532ef9834b033e8ef87eb597bc1a26aa89a2365d212	\\x00000000000001d0	10	0	payto://x-taler-bank/bank.test.taler.net/227	account-1	1565998636000000
176	\\x5b63460c0b825d0eaa613f1fca865184b48d04dc105437eb67a267109daf0f02	\\x00000000000001ce	10	0	payto://x-taler-bank/bank.test.taler.net/226	account-1	1565998626000000
177	\\x66b219ab9cd23f25e4a3d93fcc72bd87fed8ee4f85fefd13df14c8942018584f	\\x00000000000001cc	10	0	payto://x-taler-bank/bank.test.taler.net/225	account-1	1565998504000000
178	\\xbdac584b91a8b1e39cce9f2063853822e248b424f3e68d46af1c6763a7a8c77d	\\x00000000000001ca	10	0	payto://x-taler-bank/bank.test.taler.net/224	account-1	1565998007000000
179	\\x8cd98bc82b641ec56a1685ce5e308cf2657281fa219d6325a66221bb16fff090	\\x00000000000001c8	10	0	payto://x-taler-bank/bank.test.taler.net/223	account-1	1565997710000000
180	\\x82018291d5681e391d52e11f0fe99dd7af9ba088ef8a04703d47c39c1131661a	\\x00000000000001c6	10	0	payto://x-taler-bank/bank.test.taler.net/222	account-1	1565997578000000
181	\\xc77e537ef13fd7c51e61cef89d2022c16b0686ff1c55764969a96ee4c87a3052	\\x00000000000001c4	10	0	payto://x-taler-bank/bank.test.taler.net/221	account-1	1565997290000000
182	\\x1d76762600f8bd3f4795f62f03add0c65566e6688292c8646a6b5da12cacf1dc	\\x00000000000001c2	10	0	payto://x-taler-bank/bank.test.taler.net/220	account-1	1565997147000000
183	\\xfcfcdc8cd2791777397249d4c3da52e1863f55ad0c6882e2d751bbd405302095	\\x00000000000001c0	10	0	payto://x-taler-bank/bank.test.taler.net/219	account-1	1565997130000000
184	\\x3f619c26dc967addb49cae026b9f91709a030e15addc6ca6a5127e72cc930001	\\x00000000000001be	10	0	payto://x-taler-bank/bank.test.taler.net/218	account-1	1565997000000000
185	\\xf5d83929494f27bfa0a816711d37f72cb65f822e8de11668fc52aebf6ce55682	\\x00000000000001bc	10	0	payto://x-taler-bank/bank.test.taler.net/217	account-1	1565996975000000
186	\\xa4d33108e549c5f07de36bb4d46529b1e368ace2ad4c34606eb1dfff199efd6d	\\x00000000000001ba	10	0	payto://x-taler-bank/bank.test.taler.net/216	account-1	1565996970000000
187	\\x7c002a0774ba18250483639e653c545867bd19c9a7e5e469f6867be5322a772b	\\x00000000000001b8	10	0	payto://x-taler-bank/bank.test.taler.net/215	account-1	1565996963000000
188	\\xb4de597a51faf7dba502d6b7d4d08809f423fe4e25218590e3fb05ccfc2824cd	\\x00000000000001b6	10	0	payto://x-taler-bank/bank.test.taler.net/214	account-1	1565996959000000
189	\\xf7719f9def9a2234ca81e166c0233b2468cbacd10b699d3cf61a6bd46c032a81	\\x00000000000001b4	10	0	payto://x-taler-bank/bank.test.taler.net/213	account-1	1565996913000000
190	\\x6bf8404ce889b919973f0dadfd10a1497e3fd6e794b7e64c6df8011a37511623	\\x00000000000001b2	10	0	payto://x-taler-bank/bank.test.taler.net/212	account-1	1565996907000000
191	\\x5608e9a6b49d5da56c6e306f6f35d37d71f5cd1f709a4ea4403ca1335b952dbb	\\x00000000000001b0	10	0	payto://x-taler-bank/bank.test.taler.net/211	account-1	1565996895000000
192	\\x093d02b628a9974e33fcf8a6d5fc6d74c70427960d524fd8674977d819163e72	\\x00000000000001ae	10	0	payto://x-taler-bank/bank.test.taler.net/210	account-1	1565996886000000
193	\\xbb61ab42b47a032fb8809a0fd1b2cd13f509c1e922863d9e84ac188bba2ba4a2	\\x00000000000001ac	10	0	payto://x-taler-bank/bank.test.taler.net/209	account-1	1565996871000000
194	\\x231459f058a65e3e280e888cec88737c2452fcdd1317322b92898372c8eee53f	\\x00000000000001aa	10	0	payto://x-taler-bank/bank.test.taler.net/208	account-1	1565996867000000
195	\\xb800dddd6ca1525b45937f3638762afba97df01c8fd68589b332cc6af8c17f6b	\\x00000000000001a8	10	0	payto://x-taler-bank/bank.test.taler.net/207	account-1	1565996297000000
196	\\x6edc8a322e33a069a0c0fe3ad6461c677dee1f9445deb38e243ce53bce2c5606	\\x00000000000001a6	10	0	payto://x-taler-bank/bank.test.taler.net/206	account-1	1565995725000000
197	\\x12fba7c03a70173a50b46399a5d848b0639b0c59f4465af5a923fecf0306356b	\\x00000000000001a4	10	0	payto://x-taler-bank/bank.test.taler.net/205	account-1	1565992036000000
198	\\x8b90d565724439977467feb78f95468ca325a6a583ec42eb9e528ed9ee67acfd	\\x00000000000001a1	10	0	payto://x-taler-bank/bank.test.taler.net/204	account-1	1565986862000000
199	\\x52b90c06be123b6979ec5d9ba1032013ce60a91dacddbecafee7302d9ce709b7	\\x000000000000019e	10	0	payto://x-taler-bank/bank.test.taler.net/203	account-1	1565981306000000
200	\\x92077db0eb754e8074b64199e68906e04614d790042aed5d9cc84db1f80e8aca	\\x000000000000019b	5	0	payto://x-taler-bank/bank.test.taler.net/201	account-1	1565960310000000
201	\\x31b91dbf4e89506f09d918dffa3a1800813f8e7fe1a7356c3a92681f62b9066f	\\x0000000000000198	10	0	payto://x-taler-bank/bank.test.taler.net/200	account-1	1565952928000000
202	\\x6e846e63f3d4d2639febf8c3ef0bc3ff60acdb5d81de4d83e02d5ae36885a82b	\\x0000000000000195	10	0	payto://x-taler-bank/bank.test.taler.net/199	account-1	1565952822000000
203	\\xd569191f67bff925e2e14f1a15e5392546b5bbc64ff1e7de72ad32c47a3959c0	\\x0000000000000192	10	0	payto://x-taler-bank/bank.test.taler.net/198	account-1	1565952649000000
204	\\xefeeaed84eef3241f90f8713642986f5a806911a899d461f4c88e8b0af61ffe4	\\x000000000000018f	10	0	payto://x-taler-bank/bank.test.taler.net/197	account-1	1565952620000000
205	\\xc1d651a7160f70ad594d9ee5cd188d42687fe99db4c41a61fe82633e626fa083	\\x000000000000018d	10	0	payto://x-taler-bank/bank.test.taler.net/196	account-1	1565952610000000
206	\\xe57f5d46511d0e766c18a6ca9fc54d3283a2bb102eb8bfdf8e32266c74bcc241	\\x000000000000018b	10	0	payto://x-taler-bank/bank.test.taler.net/195	account-1	1565944892000000
207	\\xf04ba9bc678428207d91776a9464b3b108b58c38fa268bc1b7a227eda49819e8	\\x0000000000000189	10	0	payto://x-taler-bank/bank.test.taler.net/194	account-1	1565944821000000
208	\\xed16aa8942792639654d1f6023e09d1d650f2b8c93a63c1009efe130b00bb1ca	\\x0000000000000186	10	0	payto://x-taler-bank/bank.test.taler.net/193	account-1	1565941630000000
209	\\x0a0d4eb5d1abbb8cea07fee2ba1ed90bd1ebc7e22daf4a368a03cb1ba3ace1ad	\\x0000000000000184	10	0	payto://x-taler-bank/bank.test.taler.net/192	account-1	1565940072000000
210	\\xed3384e769e63bbb3a3b0e7e0d7a695c87cb83beb68a07aea69dbd28a02a00f0	\\x0000000000000181	10	0	payto://x-taler-bank/bank.test.taler.net/191	account-1	1565937383000000
211	\\x6fceae6ef52dfe039f42c029ded6f5083158b76460d1a4415de2a13e0d6b141a	\\x000000000000017e	10	0	payto://x-taler-bank/bank.test.taler.net/190	account-1	1565935796000000
212	\\xe079bd72ea08e0f54d38e00c0eebecf518d7e81b60d03082e929fdf76954aad4	\\x000000000000017c	10	0	payto://x-taler-bank/bank.test.taler.net/189	account-1	1565910146000000
213	\\x9be84bc3757bc122966d499f582bb9f053dd837cffebec5317e28f0076820ac9	\\x000000000000017a	10	0	payto://x-taler-bank/bank.test.taler.net/188	account-1	1565909731000000
214	\\x5e203725f5da7b3a43eb8c55bf3bc7674a8c9aaf19e5706516da2d337a623e83	\\x0000000000000178	10	0	payto://x-taler-bank/bank.test.taler.net/187	account-1	1565909725000000
215	\\xf5d0a679138775b0bd2c7025d52533a4d3c663a2a8e790fbcbf1323c7038edea	\\x0000000000000176	10	0	payto://x-taler-bank/bank.test.taler.net/186	account-1	1565909666000000
216	\\x352ca9fad07eb58ff536e649e5257e8153c2d6388f4b50caaf6464d8c312ffa5	\\x0000000000000174	10	0	payto://x-taler-bank/bank.test.taler.net/185	account-1	1565909597000000
217	\\x2e199e3752fa0de89b8336f28ac07d39e835b663da6d875321332681524ef8b2	\\x0000000000000172	10	0	payto://x-taler-bank/bank.test.taler.net/184	account-1	1565909467000000
218	\\x354145bcdd8f777d8f7450e7364e6546d3b5bb2b81e285ce342e2d57022acb5a	\\x000000000000016f	10	0	payto://x-taler-bank/bank.test.taler.net/183	account-1	1565909394000000
219	\\xf8ad117b767116b4b6ecd1946e5c8258a9d0e26f10f5aeb83a2c96d9a4e801b5	\\x000000000000016c	10	0	payto://x-taler-bank/bank.test.taler.net/182	account-1	1565909086000000
220	\\x2d841e2844b84613d06e1871ce1ff7c7aeb6e6272d643d95cf83b800d83f6fa5	\\x000000000000016a	10	0	payto://x-taler-bank/bank.test.taler.net/181	account-1	1565909049000000
221	\\x099c38804d748d134f237668a8c22970981a1666cee497cab15a5b3761d95fe2	\\x0000000000000167	10	0	payto://x-taler-bank/bank.test.taler.net/180	account-1	1565907603000000
222	\\x0534b703fcf4fb1bcc5c98894919ce8f6c647409c80ecb2f6784ea736f52a258	\\x0000000000000165	10	0	payto://x-taler-bank/bank.test.taler.net/179	account-1	1565907529000000
223	\\x4ef3a8013f6c1fd371954afdf7db5831e2a4b08a24a46d47ce0d0fe71db27450	\\x0000000000000162	10	0	payto://x-taler-bank/bank.test.taler.net/178	account-1	1565907253000000
224	\\x7e5c973417676e8adab516ab8ae8e867a929f1d5b49f19fa01cb129e1333557a	\\x000000000000015f	10	0	payto://x-taler-bank/bank.test.taler.net/177	account-1	1565906353000000
225	\\xdaf21c4d7d0506e761794bfd54286da9cccfbd5dcffec91d4de685ddeb2d9874	\\x000000000000015d	10	0	payto://x-taler-bank/bank.test.taler.net/176	account-1	1565906280000000
226	\\x37e05777be1d12227329799c20ceb6392c437fa7ff2f7cd9b73fb6942d97b674	\\x000000000000015a	10	0	payto://x-taler-bank/bank.test.taler.net/175	account-1	1565905346000000
227	\\xab61e6dc949dd1f35b2bcf8aa92155a61b37dc8ff002513db10988d72c10f85c	\\x0000000000000157	10	0	payto://x-taler-bank/bank.test.taler.net/174	account-1	1565904659000000
228	\\x9d7bdee2ad68d7850d99dc3009925e3fff8faf821c782c75b9e58d8401f492a6	\\x0000000000000154	10	0	payto://x-taler-bank/bank.test.taler.net/173	account-1	1565903993000000
229	\\xfbcab337efa5cad7f030026dd568ce0a9f6b32a3f0647b6c23d9055c4272ae38	\\x0000000000000152	10	0	payto://x-taler-bank/bank.test.taler.net/172	account-1	1565903788000000
230	\\xd24bceae2f137c7a7a33a7e27490f2ee051ca8303fee7d4dd8e78d7a1f0aee62	\\x0000000000000150	10	0	payto://x-taler-bank/bank.test.taler.net/171	account-1	1565903589000000
231	\\x5039d714051dc54f8a12d638d99d6ee2cbba8f84417d239ba13a6dae52a106d8	\\x000000000000014e	10	0	payto://x-taler-bank/bank.test.taler.net/170	account-1	1565903528000000
232	\\xe3885032e24de4aff2214d768134ee11d500559f69b92befe92a9b475fdbbeee	\\x000000000000014c	10	0	payto://x-taler-bank/bank.test.taler.net/169	account-1	1565903455000000
233	\\x92f04e72829581397d5d7af2cfbe8c1eb98769ed2a1dc49f9502e4efb1387ca4	\\x000000000000014a	10	0	payto://x-taler-bank/bank.test.taler.net/168	account-1	1565903383000000
234	\\xcbb9acd062ab443328e6050dbe93e2b8f84c6e2d06b4d98e8aace06251e06033	\\x0000000000000148	10	0	payto://x-taler-bank/bank.test.taler.net/167	account-1	1565903277000000
235	\\xe9cd9bd7e64730ffcca680c79dc186180f44228b2b64146e3e98689c074bf5a7	\\x0000000000000146	10	0	payto://x-taler-bank/bank.test.taler.net/166	account-1	1565903077000000
236	\\xe9475fffced36d5aa6e26073dd28ccc50f2ca4448b3089ecc9c13030abd8f60b	\\x0000000000000144	10	0	payto://x-taler-bank/bank.test.taler.net/165	account-1	1565902856000000
237	\\x87df20e293f6c021efdb3408e1f3121f79a5f1000cbdd3d2b09eade6969f07c8	\\x0000000000000142	10	0	payto://x-taler-bank/bank.test.taler.net/164	account-1	1565902784000000
238	\\xddb8dfe63ae9995f4846435d10bbb0b27887c5bd911082781c4efedd0df40f67	\\x0000000000000140	10	0	payto://x-taler-bank/bank.test.taler.net/163	account-1	1565902533000000
239	\\xf236ae1b03f5896bb57da63548778c065c31c5d30ca2e1b257b98e8a40a1f498	\\x000000000000013e	10	0	payto://x-taler-bank/bank.test.taler.net/162	account-1	1565901819000000
240	\\x245663abb3929008134cfadcd585d8c30189eac85a59ac3f63b57ee150394031	\\x000000000000013c	10	0	payto://x-taler-bank/bank.test.taler.net/161	account-1	1565901629000000
241	\\x7920ef3246557b9add917c3b24df7557e597b9ea132d7a6ade8147463f20d88e	\\x000000000000013a	10	0	payto://x-taler-bank/bank.test.taler.net/160	account-1	1565901302000000
242	\\x383faa3efbad6ba618b9a0518c726b968c093da880aa325e0815c26d302baa8d	\\x0000000000000138	10	0	payto://x-taler-bank/bank.test.taler.net/159	account-1	1565901249000000
243	\\x0c5cd55b9766b103527762452a1e81367c77bf6d24403a15b94ea0fa87904776	\\x0000000000000136	10	0	payto://x-taler-bank/bank.test.taler.net/158	account-1	1565900845000000
244	\\xd0310cbff1f595d844e540ff10e9e2de78fcb27fdba221f4243ec5bf69585c82	\\x0000000000000134	10	0	payto://x-taler-bank/bank.test.taler.net/157	account-1	1565900815000000
245	\\xb21a34488c76adf57605deef27a970d6d9d33da99fd10d5b34f971283282b936	\\x0000000000000132	10	0	payto://x-taler-bank/bank.test.taler.net/156	account-1	1565900324000000
246	\\x038996dfe9ad38f23e619fd7633f3074e88b03d48e59d818047613fe6617f725	\\x0000000000000130	10	0	payto://x-taler-bank/bank.test.taler.net/155	account-1	1565899745000000
247	\\xba2946c6883d1ed6f2770b5902b2b08f6ee0a02148b277b60a085f88118d3ddc	\\x000000000000012e	10	0	payto://x-taler-bank/bank.test.taler.net/154	account-1	1565899679000000
248	\\xb233d5a9840e928cb977bceb516306951f3690c14183539824dd61ee466f08c2	\\x000000000000012b	10	0	payto://x-taler-bank/bank.test.taler.net/153	account-1	1565898981000000
249	\\xa42e64a59afcf6bb9f1c76f9cb00613f067bc49f5e81b8e242d813bafccea2fc	\\x0000000000000128	10	0	payto://x-taler-bank/bank.test.taler.net/152	account-1	1565896715000000
250	\\x3ec53b2ead912ef64ac90c74d5a68e5b60ae65f0249af37ea6eb9e05b9164898	\\x0000000000000125	10	0	payto://x-taler-bank/bank.test.taler.net/151	account-1	1565888850000000
251	\\x21d76dcb3902f1dbdde706d80a37b852666435bbeca78bfdc5cef62d72686d43	\\x0000000000000122	10	0	payto://x-taler-bank/bank.test.taler.net/150	account-1	1565874286000000
252	\\xf1c90d032747f3cc1d8738eb9c888c1e4013f9e7064ffd521a7eaded85cfbc9f	\\x000000000000011f	10	0	payto://x-taler-bank/bank.test.taler.net/149	account-1	1565801356000000
253	\\xaf086d1b12d87e90235d15156afdafefe8fcd38f4de456e9bbfeb62b3d6c3ad4	\\x000000000000011c	10	0	payto://x-taler-bank/bank.test.taler.net/148	account-1	1565800433000000
254	\\x06ac13492eace96f3e5a49e44e0f18c4a356c77b1d4a8e856b976d9e9a436edc	\\x0000000000000119	10	0	payto://x-taler-bank/bank.test.taler.net/147	account-1	1565800289000000
255	\\xea06a92933ce6035f37c58c4476a5b661228594d98b62e4b8f8c2458fe451303	\\x0000000000000117	10	0	payto://x-taler-bank/bank.test.taler.net/146	account-1	1565800235000000
256	\\x64a12dded192a4f8edc3614e4acf52fbe27c78cbed3ab815f4627723ca14e4ab	\\x0000000000000114	10	0	payto://x-taler-bank/bank.test.taler.net/145	account-1	1565202594000000
257	\\xfb949fb3cf8195cd6424b1475ea365019a9a4fbb25041e94af644e201c7c83d6	\\x0000000000000111	10	0	payto://x-taler-bank/bank.test.taler.net/144	account-1	1565202402000000
258	\\xe566a9c140e79572592dfeb3dcf5cea94c9dd8da30dc292d8fe44a284ce5d481	\\x000000000000010f	10	0	payto://x-taler-bank/bank.test.taler.net/143	account-1	1565201202000000
259	\\xc2cabf67c5f7bdc043a7f62ed26cb12fd43b1492aabb44bf5db7f0d70e57dbf8	\\x000000000000010c	10	0	payto://x-taler-bank/bank.test.taler.net/142	account-1	1564696822000000
260	\\x07339becf40893d3ae5d1240e79f1f24c8289ce9ba616c570c50f7f58cd81169	\\x0000000000000109	10	0	payto://x-taler-bank/bank.test.taler.net/141	account-1	1564695804000000
261	\\x23e715a7d521c72f5b14338fea8ef018b42e255c3047d0a381ba1b892951a584	\\x0000000000000107	10	0	payto://x-taler-bank/bank.test.taler.net/140	account-1	1564695796000000
262	\\x18191bb360a5f0a52525101988c41ed8c9244511d8813371023d44164dd3ff9b	\\x0000000000000104	10	0	payto://x-taler-bank/bank.test.taler.net/139	account-1	1564694327000000
263	\\xbf0ff9a0ee337e7af907db7c46888d79a3f4e0dcc96ee1476a8bd4bb0b063a30	\\x0000000000000101	10	0	payto://x-taler-bank/bank.test.taler.net/138	account-1	1564694233000000
264	\\xdd974f8782ead8c4f65996e45e14cbdedd05b5ff194f2e069086c2918819b75c	\\x00000000000000fe	10	0	payto://x-taler-bank/bank.test.taler.net/137	account-1	1564694153000000
265	\\x24bfdf65d4f1f9d4569b886e727b9aa0dc6880614899b27f5663d8b72e1b583e	\\x00000000000000fc	10	0	payto://x-taler-bank/bank.test.taler.net/136	account-1	1564694104000000
266	\\xf03f57d32b04d85adbce1409248b6b5fb37321cd9d9cf87501d21db209336cdf	\\x00000000000000f9	10	0	payto://x-taler-bank/bank.test.taler.net/135	account-1	1564694014000000
267	\\xb808d9b7228568c2da8a58e1f0f5bab7af279d1db94592f1117e42163aeee7be	\\x00000000000000f6	10	0	payto://x-taler-bank/bank.test.taler.net/134	account-1	1564693825000000
268	\\x96b4b1dda4cf071443b4981f1d19d2f2f2e18c134355b9fee726e8f36bbdd2da	\\x00000000000000f3	10	0	payto://x-taler-bank/bank.test.taler.net/133	account-1	1564693777000000
269	\\xc18211fa8c81102e6fc987ba80a04caa028b1982b816a5d2785614d6ebec3c96	\\x00000000000000f0	10	0	payto://x-taler-bank/bank.test.taler.net/132	account-1	1564692761000000
270	\\x7085f00e9a48f4678899788358172b7447cd456c276a20d7313ca474be88b8a7	\\x00000000000000ed	10	0	payto://x-taler-bank/bank.test.taler.net/131	account-1	1564692647000000
271	\\x6803c62ef4992666d21fd5571e2807134d1aaa6f7fbb7f8333ddbab7910e0a00	\\x00000000000000eb	10	0	payto://x-taler-bank/bank.test.taler.net/130	account-1	1564692566000000
272	\\xd9639612a99db4d4527d907179d1649575ade0db21205bb984928d59916ff575	\\x00000000000000e9	10	0	payto://x-taler-bank/bank.test.taler.net/129	account-1	1564692538000000
273	\\xb4a2cee738ce45ecc226c07766148a710e68875ae06b92447f79d3615a279da7	\\x00000000000000e7	10	0	payto://x-taler-bank/bank.test.taler.net/128	account-1	1564692478000000
274	\\x66f3faced265ce5d6c8b67ca3566edf511e61b0caada94bf08ba538d01357b70	\\x00000000000000e5	10	0	payto://x-taler-bank/bank.test.taler.net/127	account-1	1564692433000000
275	\\x48df8b7cfd2999012b0004f8d0746d4c1ccf02051b6c55b071bf0bc3f92aee9c	\\x00000000000000e3	10	0	payto://x-taler-bank/bank.test.taler.net/126	account-1	1564692411000000
276	\\x548a4bc745f4033c770ed431c2321bbe70d609d881190f970251bda60052c5a5	\\x00000000000000e1	10	0	payto://x-taler-bank/bank.test.taler.net/125	account-1	1564691565000000
277	\\x63a477040824f3cd55ac8dbc628274a9107608c423fc51643ac25d2ed61d0de8	\\x00000000000000df	10	0	payto://x-taler-bank/bank.test.taler.net/124	account-1	1564691151000000
278	\\x2c1b8d0b80acb5f6e3049190ff613726a4b5441553b3d3ec77deb232594e7218	\\x00000000000000dd	10	0	payto://x-taler-bank/bank.test.taler.net/123	account-1	1564691105000000
279	\\xd78dde36de2139fa86f2a0f7bf8a13b2f654d9fc3cd303ebb2eab186cb9f0040	\\x00000000000000db	10	0	payto://x-taler-bank/bank.test.taler.net/122	account-1	1564690971000000
280	\\x1fdc52e5e5aaf87add91e7a1fec0fbf332ce7bd9c9d64154317e670798fe7fbb	\\x00000000000000d9	10	0	payto://x-taler-bank/bank.test.taler.net/121	account-1	1564614424000000
281	\\x1380f5e214357cb2e7717dff93edbdfe1a0ea3d38abaab37ab80e1c0c68ae71a	\\x00000000000000d7	10	0	payto://x-taler-bank/bank.test.taler.net/120	account-1	1564608599000000
282	\\x954518ac86a57cd7f8e87ee130a700fa82dfc8bebfe203ca3b74d2cd17e1cb26	\\x00000000000000d5	10	0	payto://x-taler-bank/bank.test.taler.net/119	account-1	1564608548000000
283	\\xbb8902b13a6baac9f348816b3c3b9ec1b3c3c806416a64c73dcc454e09227a92	\\x00000000000000d3	10	0	payto://x-taler-bank/bank.test.taler.net/118	account-1	1564608240000000
284	\\xe4d26be5cacceef7912af71ecde66d520cb080386e12e595f003247e1f936722	\\x00000000000000d1	10	0	payto://x-taler-bank/bank.test.taler.net/117	account-1	1564607402000000
285	\\x16b8099673434e13daef88b354ddde89a8ab8803a78a262ee01ff241af07951a	\\x00000000000000cf	10	0	payto://x-taler-bank/bank.test.taler.net/116	account-1	1564607300000000
286	\\xcd29f44596d41578562294edaa5f9d225da864c18d222ebc64186656208213c3	\\x00000000000000cd	10	0	payto://x-taler-bank/bank.test.taler.net/115	account-1	1564606676000000
287	\\x24f5e83ab46b9b876a6d044bdbfd86edd0d5ac06e34f822f73537f9e86ddd27e	\\x00000000000000cb	10	0	payto://x-taler-bank/bank.test.taler.net/114	account-1	1564606647000000
288	\\xa8120c712e0045d452667af538614c2ede7fa93e574b98c2568dc94f1200ed2f	\\x00000000000000c9	10	0	payto://x-taler-bank/bank.test.taler.net/113	account-1	1564606569000000
289	\\x8de9216933cf74b32a0ba183c5d47f07deb8d1ba6aeab2558d27933f8f46251a	\\x00000000000000c7	10	0	payto://x-taler-bank/bank.test.taler.net/112	account-1	1564606497000000
290	\\x86d56a0cf7a3981f71b607a9673ee2fe4ad3a8710274073cbe9dfb7ad73a2510	\\x00000000000000c5	10	0	payto://x-taler-bank/bank.test.taler.net/111	account-1	1564605529000000
291	\\x536fbc82c3257adfb45db4a7c3fea6661442a2edf4eb3413121e86916d84c559	\\x00000000000000c3	10	0	payto://x-taler-bank/bank.test.taler.net/110	account-1	1564538833000000
292	\\xc5665b33302b94735b0f53fabe3e4b28005be2cd6ea7b9f8ee133bc35f397ed3	\\x00000000000000c1	10	0	payto://x-taler-bank/bank.test.taler.net/109	account-1	1564538774000000
293	\\xa85e72dc53fad0966b30f675487aac5810e20b3bf7f36c63233bea2d1c9370e7	\\x00000000000000bf	10	0	payto://x-taler-bank/bank.test.taler.net/108	account-1	1564538601000000
294	\\x58964c1bcebf6b5513e15eb0eef739d38f1478e1cd53bf661342b9c62038cbe2	\\x00000000000000bd	10	0	payto://x-taler-bank/bank.test.taler.net/107	account-1	1564538559000000
295	\\xd3be87219e455c130fb5d5976ec829cdf39359a7d0a3e37cdabd0e42f2fad9b2	\\x00000000000000bb	10	0	payto://x-taler-bank/bank.test.taler.net/106	account-1	1564538404000000
296	\\x62d223b400193c59c2e72fbccbe09b9184ac7c1a028da0035d53461ca495555e	\\x00000000000000b9	10	0	payto://x-taler-bank/bank.test.taler.net/105	account-1	1564538347000000
297	\\x00c831aa5b629c775dc9a0175875c435262392e8ec98c820efab3c40f59c3fe8	\\x00000000000000b7	10	0	payto://x-taler-bank/bank.test.taler.net/104	account-1	1564538267000000
298	\\x1997040916524f5640cc195c47cb5c032164e8c192fa255e85a3ae9d5800660c	\\x00000000000000b5	10	0	payto://x-taler-bank/bank.test.taler.net/103	account-1	1564538197000000
299	\\xa3e78ad0d30b125cd2d8a415ca3b9a43b971ac8e43647a68064b78943ef65e7c	\\x00000000000000b3	10	0	payto://x-taler-bank/bank.test.taler.net/102	account-1	1564538175000000
300	\\x43204e72736000d5ddee27e781d5ad4b45bfde4b3e83173311189ab720af0dca	\\x00000000000000b1	10	0	payto://x-taler-bank/bank.test.taler.net/101	account-1	1564538144000000
301	\\xa6ea849bc978b07d539c37404ce74dafb28b94d46d3d929a9ddba72d176fc5fb	\\x00000000000000af	10	0	payto://x-taler-bank/bank.test.taler.net/100	account-1	1564538036000000
302	\\x35641ad074a9b19579b03e68c2bd128dd15deaf8684af5c4a346801372d41b90	\\x00000000000000ad	10	0	payto://x-taler-bank/bank.test.taler.net/99	account-1	1564537990000000
303	\\xaae06b233c96780d6afd620b1edd6f821d14a5bf432fbc5f4aeb689e7fe3d938	\\x00000000000000ab	10	0	payto://x-taler-bank/bank.test.taler.net/98	account-1	1564537954000000
304	\\x4c6d212fba5c61423aad80c8af8b1d5f3c94b267d920f53851caadf2166d49b0	\\x00000000000000a9	10	0	payto://x-taler-bank/bank.test.taler.net/97	account-1	1564537928000000
305	\\xd0c7accb37f6345703dfb0502fa150066094c681ed319b1dc2fcd234eb6fb767	\\x00000000000000a7	10	0	payto://x-taler-bank/bank.test.taler.net/96	account-1	1564537888000000
306	\\x64aed8c33abf2c05cefa50c0ecaf5e1f20201e747be1339b8d04fbb29b59cb57	\\x00000000000000a5	10	0	payto://x-taler-bank/bank.test.taler.net/95	account-1	1564537883000000
307	\\x69958928499e2c55da1ea6fb7833bd6a3e80962996c4a821fe95d05b58f96a26	\\x00000000000000a3	10	0	payto://x-taler-bank/bank.test.taler.net/94	account-1	1564537729000000
308	\\x5cb50417e9ab996297eb90960b33772f344ae83bc6ef32ebe96318d09cb331f0	\\x00000000000000a1	10	0	payto://x-taler-bank/bank.test.taler.net/93	account-1	1564537714000000
309	\\x06ea81e28c450fd05b5a0c912fef872fe3adf22a8ca70425cfd38ff2a65649e1	\\x000000000000009f	10	0	payto://x-taler-bank/bank.test.taler.net/92	account-1	1564537697000000
310	\\x81f75ad9675c95ba5078825b565c0f824f40359308975309996a4da4a5644f10	\\x000000000000009d	10	0	payto://x-taler-bank/bank.test.taler.net/91	account-1	1564537690000000
311	\\xb2c11ab01be7ce2856f045ae71e075b7773c0ee212d4fe17a6c3b7357610517d	\\x000000000000009b	10	0	payto://x-taler-bank/bank.test.taler.net/90	account-1	1564537683000000
312	\\x9656ed83ad3aa5cc92c0f8164a1be450f5f275de8ac3cbe3269a5b2bc67a4e8c	\\x0000000000000099	10	0	payto://x-taler-bank/bank.test.taler.net/89	account-1	1564537655000000
313	\\xb0f9afccc0e0e6db8ff80daafbe7e3402de21e2f37d57f22348397c5d5d28940	\\x0000000000000097	10	0	payto://x-taler-bank/bank.test.taler.net/88	account-1	1564537644000000
314	\\x302417b3226366b7893c3cf6ea0a9914d7f12ee9c4f7e68f4b0a743dddc2daad	\\x0000000000000095	10	0	payto://x-taler-bank/bank.test.taler.net/87	account-1	1564537597000000
315	\\xbebc635004c1523c36f749753b8d7df3e3a535d657529c88edda82aa8372688e	\\x0000000000000093	10	0	payto://x-taler-bank/bank.test.taler.net/86	account-1	1564537535000000
316	\\xd97382f3adeb334efc19beb626b79a465cf10e6722370f4158811962ea18bafa	\\x0000000000000091	10	0	payto://x-taler-bank/bank.test.taler.net/85	account-1	1564537486000000
317	\\x1da515d261a0b861b1c937b34bf6cbf0dfe0baf10646daec02035c888775be0f	\\x000000000000008f	10	0	payto://x-taler-bank/bank.test.taler.net/84	account-1	1564537480000000
318	\\x9f5bf80861719ced68d14c652154ef31251800dfb9b9d131fd211072cbe1dfe0	\\x000000000000008d	10	0	payto://x-taler-bank/bank.test.taler.net/83	account-1	1564537473000000
319	\\xf405b7257a8a5538d422ef6357ad1bf283cc4c11fffc5d0cfa766f72513618b6	\\x000000000000008b	10	0	payto://x-taler-bank/bank.test.taler.net/82	account-1	1564537413000000
320	\\x22f8a5abcfd602cc882981bb71b6369295be2134d32634f3f977149bcdcb58f0	\\x0000000000000089	10	0	payto://x-taler-bank/bank.test.taler.net/81	account-1	1564536410000000
321	\\xe28be2d1c6b322cf70742df0d1770adab4273af10f2a141ff703bbd24a9a9ac8	\\x0000000000000087	10	0	payto://x-taler-bank/bank.test.taler.net/80	account-1	1564536371000000
322	\\x6a0d97fb945b3b91e17b1e40f3e8b6d7b595a57e4bbffbea232987e427b5a1d1	\\x0000000000000085	10	0	payto://x-taler-bank/bank.test.taler.net/79	account-1	1564536331000000
323	\\xfb87bd1deed3e5c30cdd323ef440e77e42d859262962e9f99c03a5c740e4afaa	\\x0000000000000083	10	0	payto://x-taler-bank/bank.test.taler.net/78	account-1	1564536263000000
324	\\x312118463312133bf9537123a3930ac4a4d2c245baea11dd8fd32fd8351bed29	\\x0000000000000081	10	0	payto://x-taler-bank/bank.test.taler.net/77	account-1	1564536198000000
325	\\x4685b36210f4a6c7e87d9f88b5a45f834a0d5b58c9d138fd705aaf442e9ad8c4	\\x000000000000007f	10	0	payto://x-taler-bank/bank.test.taler.net/76	account-1	1564536071000000
326	\\xfb380400ea4f5a8fbc5b8bb4a09b779aaf217474955c02d02e6c2f7067293e2e	\\x000000000000007d	10	0	payto://x-taler-bank/bank.test.taler.net/75	account-1	1564536053000000
327	\\xbc40482ef0b8339c6ca1a7fdb65773a0e8a025c9c132fb6be01e73f7034e6e55	\\x000000000000007b	10	0	payto://x-taler-bank/bank.test.taler.net/74	account-1	1564535749000000
328	\\xd681ec996bf4ca985c7fa9577709158416c88988a29f20d8ea16dfbc27e494ff	\\x0000000000000079	10	0	payto://x-taler-bank/bank.test.taler.net/73	account-1	1564535583000000
329	\\x4deda68ee9c75e3eafa0727067c4778ca01a8e2adc85eb1a8b45035552a98578	\\x0000000000000077	10	0	payto://x-taler-bank/bank.test.taler.net/72	account-1	1564535176000000
330	\\xa83105590f3561f861081fcfd5f885a01585b325ffb3263c6a7c9c8d2a10c34c	\\x0000000000000075	10	0	payto://x-taler-bank/bank.test.taler.net/71	account-1	1564535167000000
331	\\x54b48db3c7833a4a43d7433a7443c0a43ca5eccdae6760937e9fe4c074b2a3da	\\x0000000000000073	10	0	payto://x-taler-bank/bank.test.taler.net/70	account-1	1564534808000000
332	\\xf4ce5a6636d9042b66f1633ae30b2aa5cd262a189ed20f793f72307dc9c248f0	\\x0000000000000071	10	0	payto://x-taler-bank/bank.test.taler.net/69	account-1	1564534634000000
333	\\xe6aec2213578fe4de5fee32f82d79ce13f168f9ddd1861ea50c2f13d62c9f4ad	\\x000000000000006f	10	0	payto://x-taler-bank/bank.test.taler.net/68	account-1	1564534070000000
334	\\x832ba7bf73d5b86429f3be7f245e0b8880f2e6feb29e6b3d6d5f13d586bf9fcc	\\x000000000000006d	10	0	payto://x-taler-bank/bank.test.taler.net/67	account-1	1564533855000000
335	\\xd3ff34a089de9aec918e3b75a0178136171af9a84fbee676ea5a8cc2a947c060	\\x000000000000006b	10	0	payto://x-taler-bank/bank.test.taler.net/66	account-1	1564533536000000
336	\\xe7fd68fd42067d407b98d1f30f80307353f5348047dc2649c82684240886e4fd	\\x0000000000000069	10	0	payto://x-taler-bank/bank.test.taler.net/65	account-1	1564533370000000
337	\\xb65138b306c3a742753688438123087da53e07319fc30ddb769baec37780d204	\\x0000000000000067	10	0	payto://x-taler-bank/bank.test.taler.net/64	account-1	1564533342000000
338	\\xf66b6fc40bfd70532fa6da42e8d746a20a74415647f99be6c5e5a855c97aa0a7	\\x0000000000000065	10	0	payto://x-taler-bank/bank.test.taler.net/63	account-1	1564533298000000
339	\\x95a1d91c014ba399e5f7494c4135cb3c81b0f69eeed821c85da402fc07c9daac	\\x0000000000000063	10	0	payto://x-taler-bank/bank.test.taler.net/62	account-1	1564532759000000
340	\\xcf622a2c3767c9f871100f9d782b792e1e6a5404833445d522789f924d169b4d	\\x0000000000000061	10	0	payto://x-taler-bank/bank.test.taler.net/61	account-1	1564532057000000
341	\\x8d40f84bf39a8ca60e00d36825f2b156afaad70dff784f434ddfdb48682d53b6	\\x000000000000005f	10	0	payto://x-taler-bank/bank.test.taler.net/60	account-1	1564532047000000
342	\\x5604e4942174f8ead3e75d576e38c5264e65757cc2a07c4e8ac1bf4da6b95b14	\\x000000000000005d	10	0	payto://x-taler-bank/bank.test.taler.net/59	account-1	1564531757000000
343	\\x39a22bfce8e62bb9bf56113cc0272dc3c776cac1efa3c307d0fb84671d805d76	\\x000000000000005b	10	0	payto://x-taler-bank/bank.test.taler.net/58	account-1	1564531733000000
344	\\xde8480cf26f349a625f9fcd83aa6498570479fad5c1193f9dda3f1ad683239db	\\x0000000000000059	10	0	payto://x-taler-bank/bank.test.taler.net/57	account-1	1564531462000000
345	\\xb452f9eca6986c08f8c23a978e0f0be057a8ac79005640f87a993e16b95764fa	\\x0000000000000057	10	0	payto://x-taler-bank/bank.test.taler.net/56	account-1	1564530216000000
346	\\x9f049ed6dbb886f85e6b62c86a9ce709d0d2de3abb8f6578d50233f88bc7f93d	\\x0000000000000055	10	0	payto://x-taler-bank/bank.test.taler.net/55	account-1	1564530055000000
347	\\x4e7946826a660b06b17634fc4ead6f9ce8ca563ba56eb8e9569cbcec1a279ce8	\\x0000000000000053	10	0	payto://x-taler-bank/bank.test.taler.net/54	account-1	1564529464000000
348	\\xf1c097c68600d04fd93be5c44fe7c67ee577d2c372eb981bf1889e669c1ee203	\\x0000000000000051	10	0	payto://x-taler-bank/bank.test.taler.net/53	account-1	1564529328000000
349	\\xee80e518448d549e9319687310248ea6a8885dfa94ba0f78bf62a12c84825e9e	\\x000000000000004f	10	0	payto://x-taler-bank/bank.test.taler.net/52	account-1	1564529220000000
350	\\x420480d63995c7c69bded84145ce20c13743f51cb83296d0b38713d4c3307dac	\\x000000000000004d	10	0	payto://x-taler-bank/bank.test.taler.net/51	account-1	1564527969000000
351	\\x16dcd603b509d4829fc4f2c6ed34a7fc5d20be15dcd3c50248f97e609eedf3b1	\\x000000000000004b	10	0	payto://x-taler-bank/bank.test.taler.net/50	account-1	1564527961000000
352	\\xc3109d60cc5a3adf527ad26fd6cb17223bcddf138cedd775ff8174a6b0d4d57f	\\x0000000000000049	10	0	payto://x-taler-bank/bank.test.taler.net/49	account-1	1564526700000000
353	\\x285c1be3eddd195f60d19a0d35e7d9ac677db3414e3dbeb45a744740bf2ceade	\\x0000000000000047	10	0	payto://x-taler-bank/bank.test.taler.net/48	account-1	1564526599000000
354	\\x38ab0a9f30c7bc5c524a634bd65ffa7d34fc8f1086531d20e69d055f5f6117c5	\\x0000000000000045	10	0	payto://x-taler-bank/bank.test.taler.net/47	account-1	1564519935000000
355	\\x6ce4ed71b0493afa505c82bce3cf35fbb9ab1fbedd739d56de8fd0aeef256086	\\x0000000000000043	10	0	payto://x-taler-bank/bank.test.taler.net/46	account-1	1564519865000000
356	\\xabf0b85b85cf80b41e0b39ab792ae7581b9855bfcf5e28d2a9a367476a84f754	\\x0000000000000041	10	0	payto://x-taler-bank/bank.test.taler.net/45	account-1	1564519732000000
357	\\x5022184bf2d4433c31601ce1cbd91210cf746a47ea5e2986ccaafa8f44c73cb2	\\x000000000000003f	10	0	payto://x-taler-bank/bank.test.taler.net/44	account-1	1564391061000000
358	\\x9a0403092f3d26c4f6e972e7790340048a3cd685cde9ea78564d8764434cdf9c	\\x000000000000003d	10	0	payto://x-taler-bank/bank.test.taler.net/43	account-1	1564390909000000
359	\\xcc142afa684afbda15d34a034120d2e432ff922155baa4fe9c0ee650d0ff46cb	\\x000000000000003b	10	0	payto://x-taler-bank/bank.test.taler.net/42	account-1	1564390248000000
360	\\xfc81c49fd4757e5ec657c9a2def34982bcbb006e9fe97021c0abeaf1734ec94a	\\x0000000000000039	10	0	payto://x-taler-bank/bank.test.taler.net/41	account-1	1564390176000000
361	\\x897ae32910f7abed434f0610dd49237b33e444d0f8bd249430ca3dc95a10a2af	\\x0000000000000037	10	0	payto://x-taler-bank/bank.test.taler.net/40	account-1	1564388301000000
362	\\xcc86e634723b519276a556ad6ad6b60f380f21b02032c0740ded5e35603bc478	\\x0000000000000035	10	0	payto://x-taler-bank/bank.test.taler.net/39	account-1	1564387672000000
363	\\x90daeab4cbd5cb952510b3d199f3a0fefa8d45f77902390505db05bcfed8bf99	\\x0000000000000033	10	0	payto://x-taler-bank/bank.test.taler.net/38	account-1	1564387544000000
364	\\xcd23da780b5f93611ac993fc63575d2bafacd46d2ca7a9397316ba08b70fcbb6	\\x0000000000000031	10	0	payto://x-taler-bank/bank.test.taler.net/37	account-1	1564387504000000
365	\\x2155645ea096b73957f56c776e2e785db994dcec138fc4be4c41344322197551	\\x000000000000002f	10	0	payto://x-taler-bank/bank.test.taler.net/36	account-1	1564345616000000
366	\\x7bcf85a0af25010d0df96e5826302329f4a0dba7056f7390c14e240916320a55	\\x000000000000002d	10	0	payto://x-taler-bank/bank.test.taler.net/35	account-1	1564345478000000
367	\\x09c2c3d8d54d9183221a1afdee2873370eb17cb7ae6bbe259d1770a05082ec04	\\x000000000000002b	10	0	payto://x-taler-bank/bank.test.taler.net/34	account-1	1564345270000000
368	\\x19d245eda964fadc2d68c0c1d05ee8ab761212dec72a0e151f670e9028cdf0b4	\\x0000000000000029	10	0	payto://x-taler-bank/bank.test.taler.net/33	account-1	1564345083000000
369	\\xc2caebf149e241165f50e4b82c51e322f5bef5fd0c12dcf41f4ab597cf2d0919	\\x0000000000000027	10	0	payto://x-taler-bank/bank.test.taler.net/32	account-1	1564343996000000
370	\\xb53d31ec78090b17be2ea17aedb42bf74a985215946d0674fa06c7c326fcaefe	\\x0000000000000025	10	0	payto://x-taler-bank/bank.test.taler.net/31	account-1	1564343985000000
371	\\xdfcf3f95ec6a159fd971b8afc5203432523d38ca3fac1bd0dc11cee7c67d186b	\\x0000000000000023	10	0	payto://x-taler-bank/bank.test.taler.net/30	account-1	1564178356000000
372	\\x3049fdf6ffd673a6711558e0b2cd34e53dbd3d0150407f12c896dd17056f80a9	\\x0000000000000021	10	0	payto://x-taler-bank/bank.test.taler.net/29	account-1	1564177274000000
373	\\xd8457bd02eb1f93640e440d374168378a3a26810eaf6f462e0bb48ddf5fa25b1	\\x000000000000001f	10	0	payto://x-taler-bank/bank.test.taler.net/28	account-1	1564176057000000
374	\\xac8df807cb36ef64846816ab0947cb59348b116f7cccb7fe378b486bcb06adbf	\\x000000000000001d	10	0	payto://x-taler-bank/bank.test.taler.net/27	account-1	1564175456000000
375	\\x5350dea1916bd3d4324025fa70d64fcc7ca583520e6ca4ce3ce1b56f838e8bab	\\x000000000000001b	10	0	payto://x-taler-bank/bank.test.taler.net/26	account-1	1564175435000000
376	\\x661e8a0a01acb4cbb4b3678b52e36cef107ecceb1bc34ae2c534a2105b6dbdba	\\x0000000000000019	10	0	payto://x-taler-bank/bank.test.taler.net/25	account-1	1564175012000000
377	\\x1eea5a98a6944c6daa73ff98448f602b64f5a6008af7d5ec04e0948cd12521fd	\\x0000000000000017	10	0	payto://x-taler-bank/bank.test.taler.net/24	account-1	1564173924000000
378	\\x9a76b3e571ceb844d248de54ef2edcc829a8e166da4cd0f4ee0ce1606fc49d67	\\x0000000000000015	10	0	payto://x-taler-bank/bank.test.taler.net/23	account-1	1564173802000000
379	\\x4b640f53f10a01dba1998894b439df71831eff0fdaa4bf1e149a7399a879dfa7	\\x0000000000000013	10	0	payto://x-taler-bank/bank.test.taler.net/22	account-1	1564173684000000
380	\\x18e56584f16f9f023708933014b179e9b810231b40217ecc257216ca139d6510	\\x0000000000000011	10	0	payto://x-taler-bank/bank.test.taler.net/21	account-1	1564173675000000
381	\\x2d85cac3344b67052aeaaaeac0312e3bf3814781ae182d7b11e0fa6d7c301021	\\x000000000000000f	10	0	payto://x-taler-bank/bank.test.taler.net/20	account-1	1564173636000000
382	\\xbe6c6cf37b37e4ac11f5efefffa16111e32ce79981d192ada976a329a30fda7e	\\x000000000000000d	10	0	payto://x-taler-bank/bank.test.taler.net/19	account-1	1564173511000000
764	\\xc62f3c7a8cecd7c42d5ba2ef10932ec6d52d20e20d14a93107d5cfddfbdd8abb	\\x0000000000000372	10	0	payto://x-taler-bank/bank.test.taler.net/410	account-1	1566559446000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x63015503c78b7296886d235cb5b34321d624fb1ef25f45c61ec22fbcc775aea46eddc1fcb0423b54843a99570e2b502814098743a29afa63a0a25c868a1fd7f9	\\xce8c1d02f08e0e27d703187e49f219b5216518e819db6b88c58df9cd417fcc57f2e634b71c264809f008393b55bec8e838a890480df458a42437ca46c720fda3	\\x287369672d76616c200a2028727361200a2020287320234342433941304238363638333434433546314343333445373232414130373834353234343135384146314636373138453138454443423643393243454134344330394235424130323446373041424338324243363444394139433132453236454430364544333336343045443543314330423636433539364643333746443232384341444530343342424238433237433338374537334138313231353032323335464335424136383645423338353642383644303534353037463531453034313634304144414534373331434338444638353035303037334642333436463337363946303245373031393735353430463735374544343034444142323445353423290a2020290a20290a	\\xc62f3c7a8cecd7c42d5ba2ef10932ec6d52d20e20d14a93107d5cfddfbdd8abb	\\xa8e84658730d4e3a0e7136595e7c7a428da81625f09a57802174275e8bfaecf3edb5fb023c3fe874dfc4ca7b650f40e7b616850f661449c44ae346049e90d20d	1566559451000000	8	0
2	\\xc394ad17716cc5c4ff358f47194e454625b00ebf454f1acd61bf12dbca9f17c2f5aa382913fca434a4d0face0e0e35aaff2766ad7aa576f79da9b95a532c51db	\\x413cb63dc48770bf6699e2d6508672bd2a5953ffc25dc4617948cf5da98c4e615587ef0ab59d3af1377e8e245481e2ffe69d8e84b88f643f372805ced4428b4b	\\x287369672d76616c200a2028727361200a2020287320233945434339324542323645443045333134364538424244363937463535303432463836424438393130374637343845394633423235453546384238344637343245413336373646453932364434304438444445334442413643413730364630353737383342353939374242434244303732433242343236313731413232453437363630383130414243384642453945314432423634434330414241384631363931434243413145373232393137364444433139344435374133443743344442303844393544383031453646333437343838303842353232454643354138323739333743373330433641363239383242393845454336434135384431323939423823290a2020290a20290a	\\xc62f3c7a8cecd7c42d5ba2ef10932ec6d52d20e20d14a93107d5cfddfbdd8abb	\\xf8734f489ce224547977d35b184fc57c814e46dcf90681990d98d74dc3fcaa9c893275106296e6e8f7484ef99764eadcb1ecc9d7085d615e0a3c24af3e5e6d0e	1566559451000000	2	0
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
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1145, true);


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
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON public.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_reserves_by_reserve_pub ON public.auditor_reserves USING btree (reserve_pub);


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
-- Name: auditor_denomination_pending auditor_denomination_pending_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.auditor_denominations(denom_pub_hash) ON DELETE CASCADE;


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

