/*
  This file is part of TALER
  (C) 2014 GNUnet e.V.

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
 * @file util/test_wireformats.c
 * @brief Tests for JSON validations
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */

#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"

/* Valid SEPA data */
static const char * const valid_wire_str =
    "{ \"type\":\"SEPA\", \
\"IBAN\":\"DE67830654080004822650\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";

/* IBAN has wrong country code */
static const char * const invalid_wire_str =
    "{ \"type\":\"SEPA\", \
\"IBAN\":\"XX67830654080004822650\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";

/* IBAN has wrong checksum */
static const char * const invalid_wire_str2 =
    "{ \"type\":\"SEPA\", \
\"IBAN\":\"DE67830654080004822651\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";

/* Unsupported wireformat type */
static const char * const unsupported_wire_str =
    "{ \"type\":\"unsupported\", \
\"IBAN\":\"DE67830654080004822650\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";


int
main(int argc,
     const char *const argv[])
{
  const char *unsupported[] = {
    "unsupported",
    NULL
  };
  const char *sepa[] = {
    "SEPA",
    NULL
  };
  json_t *wire;
  json_error_t error;
  int ret;

  GNUNET_log_setup ("test-json-validations", "WARNING", NULL);
  (void) memset(&error, 0, sizeof(error));
  GNUNET_assert (NULL != (wire = json_loads (unsupported_wire_str, 0, NULL)));
  GNUNET_assert (1 != TALER_json_validate_wireformat (unsupported, wire));
  json_decref (wire);
  GNUNET_assert (NULL != (wire = json_loads (invalid_wire_str, 0, NULL)));
  GNUNET_assert (1 != TALER_json_validate_wireformat (sepa, wire));
  json_decref (wire);
  GNUNET_assert (NULL != (wire = json_loads (invalid_wire_str2, 0, NULL)));
  GNUNET_assert (1 != TALER_json_validate_wireformat (sepa, wire));
  json_decref (wire);
  GNUNET_assert (NULL != (wire = json_loads (valid_wire_str, 0, &error)));
  ret = TALER_json_validate_wireformat (sepa, wire);
  json_decref (wire);
  if (1 == ret)
    return 0;
  return 1;
}
