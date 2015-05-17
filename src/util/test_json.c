/*
  This file is part of TALER
  (C) 2015 Christian Grothoff (and other contributing authors)

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
 * @file util/test_json.c
 * @brief Tests for Taler-specific crypto logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"


static int
test_amount ()
{
  json_t *j;
  struct TALER_Amount a1;
  struct TALER_Amount a2;

  GNUNET_assert (GNUNET_OK ==
		 TALER_string_to_amount ("EUR:4.3",
					 &a1));
  j = TALER_json_from_amount (&a1);
  GNUNET_assert (NULL != j);
  GNUNET_assert (GNUNET_OK ==
		 TALER_json_to_amount (j,
				       &a2));
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
  /* FIXME: implement test... */
  return 0;
}

/* end of test_json.c */
