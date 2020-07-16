/*
  This file is part of TALER
  (C) 2015, 2016, 2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
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
test_amount (void)
{
  json_t *j;
  struct TALER_Amount a1;
  struct TALER_Amount a2;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("amount", &a2),
    GNUNET_JSON_spec_end ()
  };

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4.3",
                                         &a1));
  j = json_pack ("{s:o}", "amount", TALER_JSON_from_amount (&a1));
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


static int
test_contract ()
{
  struct GNUNET_HashCode h1;
  struct GNUNET_HashCode h2;
  json_t *c1;
  json_t *c2;
  json_t *c3;

  c1 = json_pack ("{s:s, s:{s:s, s:{s:s}}}",
                  "k1", "v1",
                  "k2", "n1", "n2",
                  /***/ "_forgettable", "n1", "salt");
  GNUNET_assert (NULL != c1);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_mark_forgettable (c1,
                                                       "k1"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c1,
                                           &h1));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_part_forget (c1,
                                                  "k1"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c1,
                                           &h2));
  json_decref (c1);
  if (0 !=
      GNUNET_memcmp (&h1,
                     &h2))
  {
    GNUNET_break (0);
    return 1;
  }
  c2 = json_pack ("{s:s}",
                  "n1", "n2");
  GNUNET_assert (NULL != c2);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_mark_forgettable (c2,
                                                       "n1"));
  c3 = json_pack ("{s:s, s:o}",
                  "k1", "v1",
                  "k2", c2);
  GNUNET_assert (NULL != c3);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_mark_forgettable (c3,
                                                       "k1"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c3,
                                           &h1));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_part_forget (c2,
                                                  "n1"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c3,
                                           &h2));
  json_decref (c3);
  if (0 !=
      GNUNET_memcmp (&h1,
                     &h2))
  {
    GNUNET_break (0);
    return 1;
  }
  return 0;
}


int
main (int argc,
      const char *const argv[])
{
  (void) argc;
  (void) argv;
  GNUNET_log_setup ("test-json",
                    "WARNING",
                    NULL);
  if (0 != test_amount ())
    return 1;
  if (0 != test_contract ())
    return 2;
  return 0;
}


/* end of test_json.c */
