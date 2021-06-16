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


struct TestPath_Closure
{
  const char **object_ids;

  const json_t **parents;

  unsigned int results_length;

  int cmp_result;
};


static void
path_cb (void *cls,
         const char *object_id,
         json_t *parent)
{
  struct TestPath_Closure *cmp = cls;
  if (NULL == cmp)
    return;
  unsigned int i = cmp->results_length;
  if ((0 != strcmp (cmp->object_ids[i],
                    object_id)) ||
      (1 != json_equal (cmp->parents[i],
                        parent)))
    cmp->cmp_result = 1;
  cmp->results_length += 1;
}


static int
test_contract (void)
{
  struct GNUNET_HashCode h1;
  struct GNUNET_HashCode h2;
  json_t *c1;
  json_t *c2;
  json_t *c3;
  json_t *c4;

  c1 = json_pack ("{s:s, s:{s:s, s:{s:s}}}",
                  "k1", "v1",
                  "k2", "n1", "n2",
                  /***/ "$forgettable", "n1", "salt");
  GNUNET_assert (NULL != c1);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_mark_forgettable (c1,
                                                       "k1"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_mark_forgettable (c1,
                                                       "k2"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c1,
                                           &h1));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_part_forget (c1,
                                                  "k1"));
  /* check salt was forgotten */
  GNUNET_assert (NULL ==
                 json_object_get (json_object_get (c1,
                                                   "$forgettable"),
                                  "k1"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c1,
                                           &h2));
  if (0 !=
      GNUNET_memcmp (&h1,
                     &h2))
  {
    GNUNET_break (0);
    json_decref (c1);
    return 1;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_part_forget (json_object_get (c1,
                                                                   "k2"),
                                                  "n1"));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c1,
                                           &h2));
  if (0 !=
      GNUNET_memcmp (&h1,
                     &h2))
  {
    GNUNET_break (0);
    json_decref (c1);
    return 1;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_part_forget (c1,
                                                  "k2"));
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


  c1 = json_pack ("{s:I, s:{s:s}, s:{s:b, s:{s:s}}, s:{s:s}}",
                  "k1", 1,
                  "$forgettable", "k1", "SALT",
                  "k2", "n1", true,
                  /***/ "$forgettable", "n1", "salt",
                  "k3", "n1", "string");
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (c1,
                                           &h1));
  json_dumpf (c1, stderr, JSON_INDENT (2));
  json_decref (c1);
  {
    char *s;

    s = GNUNET_STRINGS_data_to_string_alloc (&h1,
                                             sizeof (h1));
    if (0 !=
        strcmp (s,
                "48YVST0SZJXWNG3KAD14SSK3AD0T5V01W5AE6E76DYKMJSC5BQ19M0FZ7CZP5JY26FC4AFXTXRGEVSQ1NSKPQ1DQ4GS9C4SAECG5RZ8"))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid reference hash: %s\n",
                  s);
      GNUNET_free (s);
      return 1;
    }
    GNUNET_free (s);
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
  c4 = json_pack ("{s:{s:s}, s:[{s:s}, {s:s}, {s:s}]}",
                  "abc1",
                  "xyz", "value",
                  "fruit",
                  "name", "banana",
                  "name", "apple",
                  "name", "orange");
  GNUNET_assert (NULL != c4);
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_JSON_expand_path (c4,
                                         "%.xyz",
                                         &path_cb,
                                         NULL));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_expand_path (c4,
                                         "$.nonexistent_id",
                                         &path_cb,
                                         NULL));
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_JSON_expand_path (c4,
                                         "$.fruit[n]",
                                         &path_cb,
                                         NULL));

  {
    const char *object_ids[] = { "xyz" };
    const json_t *parents[] = {
      json_object_get (c4,
                       "abc1")
    };
    struct TestPath_Closure tp = {
      .object_ids = object_ids,
      .parents = parents,
      .results_length = 0,
      .cmp_result = 0
    };
    GNUNET_assert (GNUNET_OK ==
                   TALER_JSON_expand_path (c4,
                                           "$.abc1.xyz",
                                           &path_cb,
                                           &tp));
    GNUNET_assert (1 == tp.results_length);
    GNUNET_assert (0 == tp.cmp_result);
  }
  {
    const char *object_ids[] = { "name" };
    const json_t *parents[] = {
      json_array_get (json_object_get (c4,
                                       "fruit"),
                      0)
    };
    struct TestPath_Closure tp = {
      .object_ids = object_ids,
      .parents = parents,
      .results_length = 0,
      .cmp_result = 0
    };
    GNUNET_assert (GNUNET_OK ==
                   TALER_JSON_expand_path (c4,
                                           "$.fruit[0].name",
                                           &path_cb,
                                           &tp));
    GNUNET_assert (1 == tp.results_length);
    GNUNET_assert (0 == tp.cmp_result);
  }
  {
    const char *object_ids[] = { "name", "name", "name" };
    const json_t *parents[] = {
      json_array_get (json_object_get (c4,
                                       "fruit"),
                      0),
      json_array_get (json_object_get (c4,
                                       "fruit"),
                      1),
      json_array_get (json_object_get (c4,
                                       "fruit"),
                      2)
    };
    struct TestPath_Closure tp = {
      .object_ids = object_ids,
      .parents = parents,
      .results_length = 0,
      .cmp_result = 0
    };
    GNUNET_assert (GNUNET_OK ==
                   TALER_JSON_expand_path (c4,
                                           "$.fruit[*].name",
                                           &path_cb,
                                           &tp));
    GNUNET_assert (3 == tp.results_length);
    GNUNET_assert (0 == tp.cmp_result);
  }
  json_decref (c4);
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
