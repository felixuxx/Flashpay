/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file lang.c
 * @brief Utility functions for parsing and matching RFC 7231 language strings.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Check if @a lang matches the @a language_pattern, and if so with
 * which preference.
 * See also: https://tools.ietf.org/html/rfc7231#section-5.3.1
 *
 * @param language_pattern a language preferences string
 *        like "fr-CH, fr;q=0.9, en;q=0.8, *;q=0.1"
 * @param lang the 2-digit language to match
 * @return q-weight given for @a lang in @a language_pattern, 1.0 if no weights are given;
 *         0 if @a lang is not in @a language_pattern
 */
double
TALER_language_matches (const char *language_pattern,
                        const char *lang)
{
  char *p = GNUNET_strdup (language_pattern);
  char *sptr;
  double r = 0.0;

  for (char *tok = strtok_r (p, ",", &sptr);
       NULL != tok;
       tok = strtok_r (NULL, ",", &sptr))
  {
    char *sptr2;
    char *lp = strtok_r (tok, ";", &sptr2);
    char *qp = strtok_r (NULL, ";", &sptr2);
    double q = 1.0;

    if (NULL == lp)
      continue; /* should be impossible, but makes static analysis happy */
    while (isspace ((int) *lp))
      lp++;
    if (NULL != qp)
      while (isspace ((int) *qp))
        qp++;
    GNUNET_break_op ( (NULL == qp) ||
                      (1 == sscanf (qp,
                                    "q=%lf",
                                    &q)) );
    if (0 == strcasecmp (lang,
                         lp))
      r = GNUNET_MAX (r, q);
  }
  GNUNET_free (p);
  return r;
}


/* end of lang.c */
