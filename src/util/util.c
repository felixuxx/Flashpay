/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file util.c
 * @brief Common utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_attributes.h"
#include <gnunet/gnunet_json_lib.h>


const char *
TALER_b2s (const void *buf,
           size_t buf_size)
{
  static TALER_THREAD_LOCAL char ret[9];
  struct GNUNET_HashCode hc;
  char *tmp;

  GNUNET_CRYPTO_hash (buf,
                      buf_size,
                      &hc);
  tmp = GNUNET_STRINGS_data_to_string_alloc (&hc,
                                             sizeof (hc));
  memcpy (ret,
          tmp,
          8);
  GNUNET_free (tmp);
  ret[8] = '\0';
  return ret;
}


void
TALER_denom_fee_set_hton (struct TALER_DenomFeeSetNBOP *nbo,
                          const struct TALER_DenomFeeSet *fees)
{
  TALER_amount_hton (&nbo->withdraw,
                     &fees->withdraw);
  TALER_amount_hton (&nbo->deposit,
                     &fees->deposit);
  TALER_amount_hton (&nbo->refresh,
                     &fees->refresh);
  TALER_amount_hton (&nbo->refund,
                     &fees->refund);
}


void
TALER_denom_fee_set_ntoh (struct TALER_DenomFeeSet *fees,
                          const struct TALER_DenomFeeSetNBOP *nbo)
{
  TALER_amount_ntoh (&fees->withdraw,
                     &nbo->withdraw);
  TALER_amount_ntoh (&fees->deposit,
                     &nbo->deposit);
  TALER_amount_ntoh (&fees->refresh,
                     &nbo->refresh);
  TALER_amount_ntoh (&fees->refund,
                     &nbo->refund);
}


void
TALER_global_fee_set_hton (struct TALER_GlobalFeeSetNBOP *nbo,
                           const struct TALER_GlobalFeeSet *fees)
{
  TALER_amount_hton (&nbo->history,
                     &fees->history);
  TALER_amount_hton (&nbo->account,
                     &fees->account);
  TALER_amount_hton (&nbo->purse,
                     &fees->purse);
}


void
TALER_global_fee_set_ntoh (struct TALER_GlobalFeeSet *fees,
                           const struct TALER_GlobalFeeSetNBOP *nbo)
{
  TALER_amount_ntoh (&fees->history,
                     &nbo->history);
  TALER_amount_ntoh (&fees->account,
                     &nbo->account);
  TALER_amount_ntoh (&fees->purse,
                     &nbo->purse);
}


void
TALER_wire_fee_set_hton (struct TALER_WireFeeSetNBOP *nbo,
                         const struct TALER_WireFeeSet *fees)
{
  TALER_amount_hton (&nbo->wire,
                     &fees->wire);
  TALER_amount_hton (&nbo->closing,
                     &fees->closing);
}


void
TALER_wire_fee_set_ntoh (struct TALER_WireFeeSet *fees,
                         const struct TALER_WireFeeSetNBOP *nbo)
{
  TALER_amount_ntoh (&fees->wire,
                     &nbo->wire);
  TALER_amount_ntoh (&fees->closing,
                     &nbo->closing);
}


int
TALER_global_fee_set_cmp (const struct TALER_GlobalFeeSet *f1,
                          const struct TALER_GlobalFeeSet *f2)
{
  int ret;

  ret = TALER_amount_cmp (&f1->history,
                          &f2->history);
  if (0 != ret)
    return ret;
  ret = TALER_amount_cmp (&f1->account,
                          &f2->account);
  if (0 != ret)
    return ret;
  ret = TALER_amount_cmp (&f1->purse,
                          &f2->purse);
  if (0 != ret)
    return ret;
  return 0;
}


int
TALER_wire_fee_set_cmp (const struct TALER_WireFeeSet *f1,
                        const struct TALER_WireFeeSet *f2)
{
  int ret;

  ret = TALER_amount_cmp (&f1->wire,
                          &f2->wire);
  if (0 != ret)
    return ret;
  ret = TALER_amount_cmp (&f1->closing,
                          &f2->closing);
  if (0 != ret)
    return ret;
  return 0;
}


enum GNUNET_GenericReturnValue
TALER_denom_fee_check_currency (
  const char *currency,
  const struct TALER_DenomFeeSet *fees)
{
  if (GNUNET_YES !=
      TALER_amount_is_currency (&fees->withdraw,
                                currency))
  {
    GNUNET_break (0);
    return GNUNET_NO;
  }
  if (GNUNET_YES !=
      TALER_amount_is_currency (&fees->deposit,
                                currency))
  {
    GNUNET_break (0);
    return GNUNET_NO;
  }
  if (GNUNET_YES !=
      TALER_amount_is_currency (&fees->refresh,
                                currency))
  {
    GNUNET_break (0);
    return GNUNET_NO;
  }
  if (GNUNET_YES !=
      TALER_amount_is_currency (&fees->refund,
                                currency))
  {
    GNUNET_break (0);
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Hash normalized @a j JSON object or array and
 * store the result in @a hc.
 *
 * @param j JSON to hash
 * @param[out] hc where to write the hash
 */
void
TALER_json_hash (const json_t *j,
                 struct GNUNET_HashCode *hc)
{
  char *cstr;
  size_t clen;

  cstr = json_dumps (j,
                     JSON_COMPACT | JSON_SORT_KEYS);
  GNUNET_assert (NULL != cstr);
  clen = strlen (cstr);
  GNUNET_CRYPTO_hash (cstr,
                      clen,
                      hc);
  free (cstr);
}


#ifdef __APPLE__
char *
strchrnul (const char *s,
           int c)
{
  char *value;
  value = strchr (s,
                  c);
  if (NULL == value)
    value = &s[strlen (s)];
  return value;
}


#endif


void
TALER_CRYPTO_attributes_to_kyc_prox (
  const json_t *attr,
  struct GNUNET_ShortHashCode *kyc_prox)
{
  const char *name = NULL;
  const char *birthdate = NULL;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string (TALER_ATTRIBUTE_FULL_NAME,
                               &name),
      NULL),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string (TALER_ATTRIBUTE_BIRTHDATE,
                               &birthdate),
      NULL),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (attr,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break (0);
    memset (kyc_prox,
            0,
            sizeof (*kyc_prox));
    return;
  }
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (
                   kyc_prox,
                   sizeof (*kyc_prox),
                   name,
                   (NULL == name)
                   ? 0
                   : strlen (name),
                   birthdate,
                   (NULL == birthdate)
                   ? 0
                   : strlen (birthdate),
                   NULL,
                   0));
}


/* end of util.c */
