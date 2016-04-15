/*
  This file is part of TALER
  (C) 2015, 2016 GNUnet e.V. and Inria

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
 * @file json/test_json.c
 * @brief Tests for Taler-specific crypto logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Test amount conversion from/to JSON.
 *
 * @return 0 on success
 */
static int
test_amount ()
{
  json_t *j;
  struct TALER_Amount a1;
  struct TALER_Amount a2;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount (NULL, &a2),
    GNUNET_JSON_spec_end()
  };

  GNUNET_assert (GNUNET_OK ==
		 TALER_string_to_amount ("EUR:4.3",
					 &a1));
  j = TALER_JSON_from_amount (&a1);
  GNUNET_assert (NULL != j);
  GNUNET_assert (GNUNET_OK ==
		 GNUNET_JSON_parse (j, spec,
                                    NULL, NULL));
  GNUNET_assert (0 ==
		 TALER_amount_cmp (&a1,
				   &a2));
  json_decref (j);
  return 0;
}


int
main(int argc,
     const char *const argv[])
{
  GNUNET_log_setup ("test-json",
		    "WARNING",
		    NULL);
  if (0 != test_amount ())
    return 1;
  return 0;
}

/* end of test_json.c */
