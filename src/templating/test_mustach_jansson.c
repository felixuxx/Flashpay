/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file test_mustach_jansson.c
 * @brief testcase to test the mustach/jansson integration
 * @author Florian Dold
 */
#include "platform.h"
#include "mustach-jansson.h"


static void
assert_template (const char *template,
                 json_t *root,
                 const char *expected)
{
  char *r;
  size_t sz;

  GNUNET_assert (0 == mustach_jansson (template,
                                       root,
                                       &r,
                                       &sz));
  GNUNET_assert (0 == strcmp (r,
                              expected));
  GNUNET_free (r);
}


int
main (int argc,
      char *const *argv)
{
  json_t *root = json_object ();
  json_t *arr = json_array ();
  json_t *obj = json_object ();
  json_t *contract;
  /* test 1 */
  const char *t1 = "hello world";
  const char *x1 = "hello world";
  /* test 2 */
  const char *t2 = "hello {{ v1 }}";
  const char *x2 = "hello world";
  /* test 3 */
  const char *t3 = "hello {{ v3.x }}";
  const char *x3 = "hello baz";
  /* test 4 */
  const char *t4 = "hello {{# v2 }}{{ . }}{{/ v2 }}";
  const char *x4 = "hello foobar";
  /* test 5 */
  const char *t5 = "hello {{# v3 }}{{ y }}/{{ x }}{{ z }}{{/ v3 }}";
  const char *x5 = "hello quux/baz";
  /* test 6 */
  const char *t6 = "hello {{ v2!stringify }}";
  const char *x6 = "hello [\n  \"foo\",\n  \"bar\"\n]";
  /* test 7 */
  const char *t7 = "amount: {{ amt!amount_decimal }} {{ amt!amount_currency }}";
  const char *x7 = "amount: 123.00 EUR";
  /* test 8 */
  const char *t8 = "{{^ v4 }}fallback{{/ v4 }}";
  const char *x8 = "fallback";

  /* contract test 8 (contract) */
  const char *tc = "summary: {{ summary!i18n }}";
  const char *xc_en = "summary: ENGLISH";
  const char *xc_de = "summary: DEUTSCH";
  const char *xc_fr = "summary: FRANCAISE";

  (void) argc;
  (void) argv;
  GNUNET_assert (NULL != root);
  GNUNET_assert (NULL != arr);
  GNUNET_assert (NULL != obj);
  GNUNET_assert (0 ==
                 json_object_set_new (root,
                                      "v1",
                                      json_string ("world")));
  GNUNET_assert (0 ==
                 json_object_set_new (root,
                                      "v4",
                                      json_array ()));
  GNUNET_assert (0 ==
                 json_array_append_new (arr,
                                        json_string ("foo")));
  GNUNET_assert (0 ==
                 json_array_append_new (arr,
                                        json_string ("bar")));
  GNUNET_assert (0 ==
                 json_object_set_new (root,
                                      "v2",
                                      arr));
  GNUNET_assert (0 ==
                 json_object_set_new (root,
                                      "v3",
                                      obj));
  GNUNET_assert (0 ==
                 json_object_set_new (root,
                                      "amt",
                                      json_string ("EUR:123.00")));
  GNUNET_assert (0 ==
                 json_object_set_new (obj,
                                      "x",
                                      json_string ("baz")));
  GNUNET_assert (0 ==
                 json_object_set_new (obj,
                                      "y",
                                      json_string ("quux")));
  contract = json_pack ("{ s:s, s:{s:s, s:s}}",
                        "summary",
                        "ENGLISH",
                        "summary_i18n",
                        "de",
                        "DEUTSCH",
                        "fr",
                        "FRANCAISE");
  GNUNET_assert (NULL != contract);

  assert_template (t1, root, x1);
  assert_template (t2, root, x2);
  assert_template (t3, root, x3);
  assert_template (t4, root, x4);
  assert_template (t5, root, x5);
  assert_template (t6, root, x6);
  assert_template (t7, root, x7);
  assert_template (t8, root, x8);
  assert_template (tc, contract, xc_en);

  GNUNET_assert (0 ==
                 json_object_set_new (contract,
                                      "$language",
                                      json_string ("de")));
  assert_template (tc, contract, xc_de);

  GNUNET_assert (0 ==
                 json_object_set_new (contract,
                                      "$language",
                                      json_string ("fr")));
  assert_template (tc, contract, xc_fr);

  GNUNET_assert (0 ==
                 json_object_set_new (contract,
                                      "$language",
                                      json_string ("it")));
  assert_template (tc, contract, xc_en);
  json_decref (root);
  json_decref (contract);
  return 0;
}
