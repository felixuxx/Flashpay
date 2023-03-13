/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file util/crypto_confirmation.c
 * @brief confirmation computation
 * @author Christian Grothoff
 * @author Priscilla Huang
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_db_lib.h>
#include <gcrypt.h>

/**
 * How long is a TOTP code valid?
 */
#define TOTP_VALIDITY_PERIOD GNUNET_TIME_relative_multiply ( \
    GNUNET_TIME_UNIT_SECONDS, 30)

/**
 * Range of time we allow (plus-minus).
 */
#define TIME_INTERVAL_RANGE 2


/**
 * Compute TOTP code at current time with offset
 * @a time_off for the @a key.
 *
 * @param ts current time
 * @param time_off offset to apply when computing the code
 * @param key pos_key in binary
 * @param key_size number of bytes in @a key
 */
static uint64_t
compute_totp (struct GNUNET_TIME_Timestamp ts,
              int time_off,
              const void *key,
              size_t key_size)
{
  struct GNUNET_TIME_Absolute now;
  time_t t;
  uint64_t ctr;
  uint8_t hmac[20]; /* SHA1: 20 bytes */

  now = ts.abs_time;
  while (time_off < 0)
  {
    now = GNUNET_TIME_absolute_subtract (now,
                                         TOTP_VALIDITY_PERIOD);
    time_off++;
  }
  while (time_off > 0)
  {
    now = GNUNET_TIME_absolute_add (now,
                                    TOTP_VALIDITY_PERIOD);
    time_off--;
  }
  t = now.abs_value_us / GNUNET_TIME_UNIT_SECONDS.rel_value_us;
  ctr = GNUNET_htonll (t / 30LLU);

  {
    gcry_md_hd_t md;
    const unsigned char *mc;

    GNUNET_assert (GPG_ERR_NO_ERROR ==
                   gcry_md_open (&md,
                                 GCRY_MD_SHA1,
                                 GCRY_MD_FLAG_HMAC));
    gcry_md_setkey (md,
                    key,
                    key_size);
    gcry_md_write (md,
                   &ctr,
                   sizeof (ctr));
    mc = gcry_md_read (md,
                       GCRY_MD_SHA1);
    GNUNET_assert (NULL != mc);
    memcpy (hmac,
            mc,
            sizeof (hmac));
    gcry_md_close (md);
  }

  {
    uint32_t code = 0;
    int offset;

    offset = hmac[sizeof (hmac) - 1] & 0x0f;
    for (int count = 0; count < 4; count++)
      code |= hmac[offset + 3 - count] << (8 * count);
    code &= 0x7fffffff;
    /* always use 8 digits (maximum) */
    code = code % 100000000;
    return code;
  }
}


/**
 * Compute RFC 3548 base32 decoding of @a val and write
 * result to @a udata.
 *
 * @param val value to decode
 * @param val_size number of bytes in @a val
 * @param key is the val in bits
 * @param key_len is the size of @a key
 */
static int
base32decode (const char *val,
              size_t val_size,
              void *key,
              size_t key_len)
{
  /**
   * 32 characters for decoding, using RFC 3548.
   */
  static const char *decTable__ = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  unsigned char *udata = key;
  unsigned int wpos = 0;
  unsigned int rpos = 0;
  unsigned int bits = 0;
  unsigned int vbit = 0;

  while ((rpos < val_size) || (vbit >= 8))
  {
    if ((rpos < val_size) && (vbit < 8))
    {
      char c = val[rpos++];
      if (c == '=')   // padding character
      {
        break;
      }
      const char *p = strchr (decTable__, toupper (c));
      if (! p)
      { // invalid character
        return -1;
      }
      bits = (bits << 5) | (p - decTable__);
      vbit += 5;
    }
    if (vbit >= 8)
    {
      udata[wpos++] = (bits >> (vbit - 8)) & 0xFF;
      vbit -= 8;
    }
  }
  return wpos;
}


static char *
executive_totp (void *h_key,
                size_t h_key_len,
                struct GNUNET_TIME_Timestamp ts)
{
  uint64_t code; /* totp code */
  char *ret;
  ret = NULL;

  for (int i = -TIME_INTERVAL_RANGE; i<= TIME_INTERVAL_RANGE; i++)
  {
    code = compute_totp (ts,
                         i,
                         h_key,
                         h_key_len);
    if (NULL == ret)
    {
      GNUNET_asprintf (&ret,
                       "%llu",
                       (unsigned long long) code);
    }
    else
    {
      char *tmp;

      GNUNET_asprintf (&tmp,
                       "%s\n%llu",
                       ret,
                       (unsigned long long) code);
      GNUNET_free (ret);
      ret = tmp;
    }
  }
  return ret;

}


/**
 * It is build pos confirmation to verify payment.
 *
 * @param pos_key base32 (RFC 3548, not Crockford!) encoded key for verification payment
 * @param pos_alg algorithm to compute the payment verification
 * @param total of the order paid
 * @param ts is the current time given
 */
char *
TALER_build_pos_confirmation (const char *pos_key,
                              enum TALER_MerchantConfirmationAlgorithm pos_alg,
                              const struct TALER_Amount *total,
                              struct GNUNET_TIME_Timestamp ts)
{
  size_t pos_key_length = strlen (pos_key);
  void *key; /* pos_key in binary */
  size_t key_len; /* length of the key */
  char *ret;
  int dret;

  if (TALER_MCA_NONE == pos_alg)
    return NULL;
  key_len = pos_key_length * 5 / 8;
  key = GNUNET_malloc (key_len);
  dret = base32decode (pos_key,
                       pos_key_length,
                       key,
                       key_len);
  if (-1 == dret)
  {
    GNUNET_free (key);
    GNUNET_break_op (0);
    return NULL;
  }
  GNUNET_assert (dret <= key_len);
  key_len = (size_t) dret;
  switch (pos_alg)
  {
  case TALER_MCA_NONE:
    GNUNET_break (0);
    GNUNET_free (key);
    return NULL;
  case TALER_MCA_WITHOUT_PRICE: /* and 30s */
    /* Return all T-OTP codes in range separated by new lines, e.g.
       "12345678
        24522552
        25262425
        42543525
        25253552"
    */
    ret = executive_totp (key,
                          key_len,
                          ts);
    GNUNET_free (key);
    return ret;
  case TALER_MCA_WITH_PRICE:
    {
      struct GNUNET_HashCode hkey;
      struct TALER_AmountNBO ntotal;

      TALER_amount_hton (&ntotal,
                         total);
      GNUNET_assert (GNUNET_YES ==
                     GNUNET_CRYPTO_kdf (&hkey,
                                        sizeof (hkey),
                                        &ntotal,
                                        sizeof (ntotal),
                                        key,
                                        key_len,
                                        NULL,
                                        0));
      GNUNET_free (key);
      ret = executive_totp (&hkey,
                            sizeof(hkey),
                            ts);
      GNUNET_free (key);
      return ret;
    }
  }
  GNUNET_free (key);
  GNUNET_break (0);
  return NULL;
}
