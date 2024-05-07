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
#include <unistr.h>


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
  GNUNET_memcpy (ret,
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
 * Dump character in the low range into @a buf
 * following RFC 8785.
 *
 * @param[in,out] buf buffer to modify
 * @param val value to dump
 */
static void
lowdump (struct GNUNET_Buffer *buf,
         unsigned char val)
{
  char scratch[7];

  switch (val)
  {
  case 0x8:
    GNUNET_buffer_write (buf,
                         "\\b",
                         2);
    break;
  case 0x9:
    GNUNET_buffer_write (buf,
                         "\\t",
                         2);
    break;
  case 0xA:
    GNUNET_buffer_write (buf,
                         "\\n",
                         2);
    break;
  case 0xC:
    GNUNET_buffer_write (buf,
                         "\\f",
                         2);
    break;
  case 0xD:
    GNUNET_buffer_write (buf,
                         "\\r",
                         2);
    break;
  default:
    GNUNET_snprintf (scratch,
                     sizeof (scratch),
                     "\\u%04x",
                     (unsigned int) val);
    GNUNET_buffer_write (buf,
                         scratch,
                         6);
    break;
  }
}


size_t
TALER_rfc8785encode (char **inp)
{
  struct GNUNET_Buffer buf = { 0 };
  size_t left = strlen (*inp) + 1;
  size_t olen;
  char *in = *inp;
  const char *pos = in;

  GNUNET_buffer_prealloc (&buf,
                          left + 40);
  buf.warn_grow = 0; /* disable, + 40 is just a wild guess */
  while (1)
  {
    int mbl = u8_mblen ((unsigned char *) pos,
                        left);
    unsigned char val;

    if (0 == mbl)
      break;
    val = (unsigned char) *pos;
    if ( (1 == mbl) &&
         (val <= 0x1F) )
    {
      /* Should not happen, as input is produced by
       * JSON stringification */
      GNUNET_break (0);
      lowdump (&buf,
               val);
    }
    else if ( (1 == mbl) && ('\\' == *pos) )
    {
      switch (*(pos + 1))
      {
      case '\\':
        mbl = 2;
        GNUNET_buffer_write (&buf,
                             pos,
                             mbl);
        break;
      case 'u':
        {
          unsigned int num;
          uint32_t n32;
          unsigned char res[8];
          size_t rlen;

          GNUNET_assert ( (1 ==
                           sscanf (pos + 2,
                                   "%4x",
                                   &num)) ||
                          (1 ==
                           sscanf (pos + 2,
                                   "%4X",
                                   &num)) );
          mbl = 6;
          n32 = (uint32_t) num;
          rlen = sizeof (res);
          u32_to_u8 (&n32,
                     1,
                     res,
                     &rlen);
          if ( (1 == rlen) &&
               (res[0] <= 0x1F) )
          {
            lowdump (&buf,
                     res[0]);
          }
          else
          {
            GNUNET_buffer_write (&buf,
                                 (const char *) res,
                                 rlen);
          }
        }
        break;
      default:
        mbl = 2;
        GNUNET_buffer_write (&buf,
                             pos,
                             mbl);
        break;
      }
    }
    else
    {
      GNUNET_buffer_write (&buf,
                           pos,
                           mbl);
    }
    left -= mbl;
    pos += mbl;
  }

  /* 0-terminate buffer */
  GNUNET_buffer_write (&buf,
                       "",
                       1);
  GNUNET_free (in);
  *inp = GNUNET_buffer_reap (&buf,
                             &olen);
  return olen;
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
  clen = TALER_rfc8785encode (&cstr);
  GNUNET_CRYPTO_hash (cstr,
                      clen,
                      hc);
  GNUNET_free (cstr);
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


/* end of util.c */
