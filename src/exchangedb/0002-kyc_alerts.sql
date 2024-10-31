--
-- This file is part of TALER
-- Copyright (C) 2014--2022 Taler Systems SA
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

CREATE TABLE kyc_alerts
  (h_payto BYTEA PRIMARY KEY CHECK (LENGTH(h_payto)=32)
  ,trigger_type INT4 NOT NULL
  ,UNIQUE(trigger_type,h_payto)
  );
COMMENT ON TABLE kyc_alerts
  IS 'alerts about completed KYC events reliably notifying other components (even if they are not running)';
COMMENT ON COLUMN kyc_alerts.h_payto
  IS 'hash of the normalized payto://-URI for which the KYC status changed';
COMMENT ON COLUMN kyc_alerts.trigger_type
  IS 'identifies the receiver of the alert, as the same h_payto may require multiple components to be notified';
