/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file util/test_json_validations.c
 * @brief Tests for JSON validations
 * @author Sree Harsha Totakura <sreeharsha@totakura.in> 
 */

#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"

static const char * const json_wire_str =
    "{ \"type\":\"SEPA\", \
\"IBAN\":\"DE67830654080004822650\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"edate\":\"1449930207000\",                                \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";

int main(int argc, const char *const argv[])
{
  json_t *wire;
  json_error_t error;
  int ret;

  GNUNET_log_setup ("test-json-validations", "WARNING", NULL);
  (void) memset(&error, 0, sizeof(error));
  wire = json_loads (json_wire_str, 0, &error);
  if (NULL == wire)
  {
    TALER_json_warn (error);
    return 2;
  }
  ret = TALER_json_validate_wireformat ("SEPA", wire);
  if (1 == ret)
    return 0;
  return 1;
}
