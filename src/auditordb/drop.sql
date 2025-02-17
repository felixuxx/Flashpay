--
-- This file is part of TALER
-- Copyright (C) 2014--2020 Taler Systems SA
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

WITH xpatches AS (
  SELECT patch_name
  FROM _v.patches
  WHERE starts_with(patch_name,'auditor-')
)
  SELECT _v.unregister_patch(xpatches.patch_name)
  FROM xpatches;

DROP SCHEMA auditor CASCADE;

-- And we're out of here...
COMMIT;
