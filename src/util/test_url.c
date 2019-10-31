/*
  This file is part of TALER
  (C) 2015 GNUnet e.V.

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
 * @file util/test_url.c
 * @brief Tests for url helpers
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Check and free result.
 *
 * @param input to check and free
 * @param expected expected input
 */
static void
cf (char *input, char *expected)
{
  if (0 != strcmp (input, expected))
  {
    printf ("got '%s' but expected '%s'\n", input, expected);
    GNUNET_assert (0);
  }
  GNUNET_free (input);
}


int
main (int argc,
      const char *const argv[])
{

  cf (TALER_urlencode (""), "");
  cf (TALER_urlencode ("abc"), "abc");
  cf (TALER_urlencode ("~~"), "~~");
  cf (TALER_urlencode ("foo bar"), "foo%20bar");
  cf (TALER_urlencode ("foo bar "), "foo%20bar%20");
  cf (TALER_urlencode ("% % "), "%25%20%25%20");

  cf (TALER_url_join ("https://taler.net/", "foo", NULL),
      "https://taler.net/foo");
  cf (TALER_url_join ("https://taler.net/", "foo", NULL),
      "https://taler.net/foo");

  cf (TALER_url_join ("https://taler.net/", "foo", "x", "42", NULL),
      "https://taler.net/foo?x=42");
  cf (TALER_url_join ("https://taler.net/", "foo", "x", "42", "y", "bla", NULL),
      "https://taler.net/foo?x=42&y=bla");
  cf (TALER_url_join ("https://taler.net/", "foo", "x", NULL, "y", "bla", NULL),
      "https://taler.net/foo?y=bla");
  cf (TALER_url_join ("https://taler.net/", "foo", "x", "", "y", "1", NULL),
      "https://taler.net/foo?x=&y=1");

  cf (TALER_url_join ("https://taler.net/", "foo/bar", "x", "a&b", NULL),
      "https://taler.net/foo/bar?x=a%26b");

  /* Path component is not encoded! */
  cf (TALER_url_join ("https://taler.net/", "foo/bar?spam=eggs&quux=", NULL),
      "https://taler.net/foo/bar?spam=eggs&quux=");

  cf (TALER_url_absolute_raw ("https", "taler.net", "foo/bar", "baz",
                              "x", "a&b",
                              "c", "d",
                              "e", "",
                              NULL),
      "https://taler.net/foo/bar/baz?x=a%26b&c=d&e=");

  return 0;
}


/* end of test_url.c */
