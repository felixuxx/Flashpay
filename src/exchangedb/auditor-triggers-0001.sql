--
-- This file is part of TALER
-- Copyright (C) 2024 Taler Systems SA
--
-- TALER is free software; you can redistribute it and/or modify it under the
-- terms of the GNU General Public License as published by the Free Software
-- Foundation; either version 3, or (at your option) any later version.
--
-- TALER is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
-- A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with
-- TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
--

-- Everything in one big transaction
BEGIN;

--SELECT _v.register_patch('auditor-triggers-0001');

/*
CREATE OR REPLACE FUNCTION auditor_new_deposits_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY XFIXME;
    RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_new_deposits_trigger()
    IS 'Call XXX on new entry';

CREATE TRIGGER auditor_notify_helper_insert_deposits
    AFTER INSERT
    ON exchange.batch_deposits
EXECUTE PROCEDURE auditor_new_deposits_trigger();
*/


-- make 6 of these functions, one for each helper

-- the coins helper listens to this trigger
CREATE OR REPLACE FUNCTION auditor_wake_coins_helper_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY X5V5R0DDFMXS0R3W058R3W4RPDVMK35YZCS0S5VZS583J0NR0PE2G;
RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_wake_coins_helper_trigger()
    IS 'Call auditor_call_db_notify on new entry';


-- the purses helper listens to this trigger
CREATE OR REPLACE FUNCTION auditor_wake_purses_helper_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY X908G8PNPMJYA59YGGTJND1TKTBFNG8C7TREHG3X5SJ9EQAJY4Z00;
RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_wake_purses_helper_trigger()
    IS 'Call auditor_call_db_notify on new entry';


-- the deposits helper listens to this trigger
CREATE OR REPLACE FUNCTION auditor_wake_deposits_helper_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY XZD0FASMJD3XCY3Z0CGXNJQ8CMWSCW80JN6796098N71CXPH70TQ0;
RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_wake_deposits_helper_trigger()
    IS 'Call auditor_call_db_notify on new entry';

-- the reserves helper listens to this trigger
CREATE OR REPLACE FUNCTION auditor_wake_reserves_helper_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY XMF69RJQB7EN06KGSQ02VFD3723CE86VXA5GRE8H7XNNS6BDYF0G0;
RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_wake_reserves_helper_trigger()
    IS 'Call auditor_call_db_notify on new entry';

-- the wire helper listens to this trigger
CREATE OR REPLACE FUNCTION auditor_wake_wire_helper_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY X1RYYSTS139MBHVEXJ6CZZTY76MAMEEF87SRRWC8WM00HCCW6D12G;
RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_wake_wire_helper_trigger()
    IS 'Call auditor_call_db_notify on new entry';

-- the wire aggregation listens to this trigger
CREATE OR REPLACE FUNCTION auditor_wake_aggregation_helper_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY XWRPZ889FPA6TMGJ15JVTCMKEFVJEWCEKF1TEZHTDQHBYSV49M31G;
RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_wake_aggregation_helper_trigger()
    IS 'Call auditor_call_db_notify on new entry';


-- call the functions in each table to call all relevant helpers
CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation0
    AFTER INSERT ON exchange.batch_deposits
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation1
    AFTER INSERT ON exchange.partners
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation2
    AFTER INSERT ON exchange.wire_targets
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation3
    AFTER INSERT ON exchange.reserves_open_deposits
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation4
    AFTER INSERT ON exchange.aggregation_tracking
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation5
    AFTER INSERT ON exchange.purse_requests
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation6
    AFTER INSERT ON exchange.refresh_revealed_coins
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation7
    AFTER INSERT ON exchange.reserves
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation8
    AFTER INSERT ON exchange.purse_deposits
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation9
    AFTER INSERT ON exchange.reserves_out
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation10
    AFTER INSERT ON exchange.recoup
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation11
    AFTER INSERT ON exchange.coin_history
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation12
    AFTER INSERT ON exchange.coin_deposits
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation13
    AFTER INSERT ON exchange.wire_out
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation14
    AFTER INSERT ON exchange.refunds
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation15
    AFTER INSERT ON exchange.refresh_commitments
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation16
    AFTER INSERT ON exchange.purse_decision
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation17
    AFTER INSERT ON exchange.known_coins
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_aggregation18
    AFTER INSERT ON exchange.recoup_refresh
EXECUTE FUNCTION auditor_wake_aggregation_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins0
    AFTER INSERT ON exchange.purse_merges
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins1
    AFTER INSERT ON exchange.batch_deposits
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins2
    AFTER INSERT ON exchange.partners
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins3
    AFTER INSERT ON exchange.denomination_revocations
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins4
    AFTER INSERT ON exchange.wire_targets
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins5
    AFTER INSERT ON exchange.auditors
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins6
    AFTER INSERT ON exchange.purse_requests
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins7
    AFTER INSERT ON exchange.refresh_revealed_coins
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins8
    AFTER INSERT ON exchange.reserves
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins9
    AFTER INSERT ON exchange.purse_deposits
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins10
    AFTER INSERT ON exchange.reserves_out
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins11
    AFTER INSERT ON exchange.recoup
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins12
    AFTER INSERT ON exchange.auditor_denom_sigs
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins13
    AFTER INSERT ON exchange.coin_deposits
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins14
    AFTER INSERT ON exchange.refunds
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins15
    AFTER INSERT ON exchange.refresh_commitments
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins16
    AFTER INSERT ON exchange.purse_decision
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins17
    AFTER INSERT ON exchange.known_coins
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_coins18
    AFTER INSERT ON exchange.recoup_refresh
EXECUTE FUNCTION auditor_wake_coins_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses0
    AFTER INSERT ON exchange.purse_merges
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses1
    AFTER INSERT ON exchange.account_merges
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses2
    AFTER INSERT ON exchange.purse_deposits
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses3
    AFTER INSERT ON exchange.global_fee
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses4
    AFTER INSERT ON exchange.purse_requests
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses5
    AFTER INSERT ON exchange.partners
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses6
    AFTER INSERT ON exchange.purse_decision
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_purses7
    AFTER INSERT ON exchange.known_coins
EXECUTE FUNCTION auditor_wake_purses_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_deposits0
    AFTER INSERT ON exchange.wire_targets
EXECUTE FUNCTION auditor_wake_deposits_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_deposits1
    AFTER INSERT ON exchange.batch_deposits
EXECUTE FUNCTION auditor_wake_deposits_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_deposits2
    AFTER INSERT ON exchange.known_coins
EXECUTE FUNCTION auditor_wake_deposits_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_deposits3
    AFTER INSERT ON exchange.coin_deposits
EXECUTE FUNCTION auditor_wake_deposits_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves0
    AFTER INSERT ON exchange.wire_fee
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves1
    AFTER INSERT ON exchange.reserves
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves2
    AFTER INSERT ON exchange.reserves_close
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves3
    AFTER INSERT ON exchange.purse_merges
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves4
    AFTER INSERT ON exchange.wire_targets
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves5
    AFTER INSERT ON exchange.reserves_out
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves6
    AFTER INSERT ON exchange.recoup
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves7
    AFTER INSERT ON exchange.purse_requests
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves8
    AFTER INSERT ON exchange.reserves_open_requests
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves9
    AFTER INSERT ON exchange.denomination_revocations
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves10
    AFTER INSERT ON exchange.purse_decision
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves11
    AFTER INSERT ON exchange.known_coins
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_reserves12
    AFTER INSERT ON exchange.reserves_in
EXECUTE FUNCTION auditor_wake_reserves_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_wire0
    AFTER INSERT ON exchange.reserves
EXECUTE FUNCTION auditor_wake_wire_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_wire1
    AFTER INSERT ON exchange.wire_targets
EXECUTE FUNCTION auditor_wake_wire_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_wire2
    AFTER INSERT ON exchange.aggregation_tracking
EXECUTE FUNCTION auditor_wake_wire_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_wire3
    AFTER INSERT ON exchange.wire_out
EXECUTE FUNCTION auditor_wake_wire_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_wire4
    AFTER INSERT ON exchange.reserves_close
EXECUTE FUNCTION auditor_wake_wire_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_wire5
    AFTER INSERT ON exchange.profit_drains
EXECUTE FUNCTION auditor_wake_wire_helper_trigger();


CREATE OR REPLACE TRIGGER auditor_exchange_notify_helper_wire6
    AFTER INSERT ON exchange.reserves_in
EXECUTE FUNCTION auditor_wake_wire_helper_trigger();

COMMIT;
