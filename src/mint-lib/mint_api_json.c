/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mint-lib/mint_api_json.c
 * @brief functions to parse incoming requests (JSON snippets)
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include "mint_api_json.h"


/**
 * Parse absolute time specified in JSON format.  The JSON format is
 * "/TIMEVAL/" where TIMEVAL is in milliseconds.  Additionally, we
 * support "/forever/" to represent the end of time.
 *
 * @param f json specification of the amount
 * @param[out] time set to the time specified in @a f
 * @return
 *    #GNUNET_YES if parsing was successful
 *    #GNUNET_SYSERR on errors
 */
static int
parse_time_abs (json_t *f,
                struct GNUNET_TIME_Absolute *time)
{
  const char *val;
  size_t slen;
  unsigned long long int tval;
  char *endp;

  val = json_string_value (f);
  if (NULL == val)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  slen = strlen (val);
  if ( (slen <= 2) ||
       ('/' != val[0]) ||
       ('/' != val[slen - 1]) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 == strcasecmp (val,
                       "/forever/"))
  {
    *time = GNUNET_TIME_UNIT_FOREVER_ABS;
    return GNUNET_OK;
  }
  tval = strtoull (&val[1],
                   &endp,
                   10);
  if (&val[slen - 1] != endp)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* Time is in 'ms' in JSON, but in microseconds in GNUNET_TIME_Absolute */
  time->abs_value_us = tval * 1000LL;
  if ( (time->abs_value_us) / 1000LL != tval)
  {
    /* Integer overflow */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Parse amount specified in JSON format.
 *
 * @param f json specification of the amount
 * @param[out] amount set to the amount specified in @a f
 * @return
 *    #GNUNET_OK if parsing was successful
 *    #GNUNET_SYSERR on error
 */
static int
parse_amount (json_t *f,
              struct TALER_Amount *amount)
{
  json_int_t value;
  json_int_t fraction;
  const char *currency;

  memset (amount,
          0,
          sizeof (struct TALER_Amount));
  if (-1 == json_unpack (f,
                         "{s:I, s:I, s:s}",
                         "value", &value,
                         "fraction", &fraction,
                         "currency", &currency))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (value < 0) ||
       (fraction < 0) ||
       (value > UINT64_MAX) ||
       (fraction > UINT32_MAX) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (strlen (currency) >= TALER_CURRENCY_LEN)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  amount->value = (uint64_t) value;
  amount->fraction = (uint32_t) fraction;
  strcpy (amount->currency, currency);
  (void) TALER_amount_normalize (amount);
  return GNUNET_OK;
}


/**
 * Navigate and parse data in a JSON tree.
 *
 * @param root the JSON node to start the navigation at.
 * @param spec parse specification array
 * @return offset in @a spec where parsing failed, -1 on success (!)
 */
static int
parse_json (json_t *root,
            struct MAJ_Specification *spec)
{
  int i;
  json_t *pos; /* what's our current position? */

  pos = root;
  for (i=0;MAJ_CMD_END != spec[i].cmd;i++)
  {
    pos = json_object_get (root,
                           spec[i].field);
    if (NULL == pos)
    {
      GNUNET_break_op (0);
      return i;
    }
    switch (spec[i].cmd)
    {
    case MAJ_CMD_END:
      GNUNET_assert (0);
      return i;
    case MAJ_CMD_AMOUNT:
      if (GNUNET_OK !=
          parse_amount (pos,
                        spec[i].details.amount))
        return i;
      break;
    case MAJ_CMD_TIME_ABSOLUTE:
      if (GNUNET_OK !=
          parse_time_abs (pos,
                          spec[i].details.abs_time))
        return i;
      break;

    case MAJ_CMD_BINARY_FIXED:
      {
        const char *str;
        int res;

        str = json_string_value (pos);
        if (NULL == str)
        {
          GNUNET_break_op (0);
          return i;
        }
        res = GNUNET_STRINGS_string_to_data (str, strlen (str),
                                             spec[i].details.fixed_data.dest,
                                             spec[i].details.fixed_data.dest_len);
        if (GNUNET_OK != res)
        {
          GNUNET_break_op (0);
          return i;
        }
      }
      break;

    case MAJ_CMD_BINARY_VARIABLE:
      {
        const char *str;
        size_t len;
        void *data;
        int res;

        str = json_string_value (pos);
        if (NULL == str)
        {
          GNUNET_break_op (0);
          return i;
        }
        len = (strlen (str) * 5) / 8;
        if (len >= 1024)
        {
          GNUNET_break_op (0);
          return i;
        }
        data = GNUNET_malloc (len);
        res = GNUNET_STRINGS_string_to_data (str, strlen (str),
                                             data,
                                             len);
        if (GNUNET_OK != res)
        {
          GNUNET_break_op (0);
          GNUNET_free (data);
          return i;
        }
        *spec[i].details.variable_data.dest_p = data;
        *spec[i].details.variable_data.dest_len_p = len;
      }
      break;

    case MAJ_CMD_RSA_PUBLIC_KEY:
      {
        size_t len;
        const char *str;
        int res;
        void *buf;

        str = json_string_value (root);
        if (NULL == str)
        {
          GNUNET_break_op (0);
          return i;
        }
        len = (strlen (str) * 5) / 8;
        buf = GNUNET_malloc (len);
        res = GNUNET_STRINGS_string_to_data (str,
                                             strlen (str),
                                             buf,
                                             len);
        if (GNUNET_OK != res)
        {
          GNUNET_free (buf);
          GNUNET_break_op (0);
          return i;
        }
        *spec[i].details.rsa_public_key
          = GNUNET_CRYPTO_rsa_public_key_decode (buf,
                                                 len);
        GNUNET_free (buf);
        if (NULL == spec[i].details.rsa_public_key)
        {
          GNUNET_break_op (0);
          return i;
        }
      }
      break;

    case MAJ_CMD_RSA_SIGNATURE:
      {
        size_t len;
        const char *str;
        int res;
        void *buf;

        str = json_string_value (root);
        if (NULL == str)
        {
          GNUNET_break_op (0);
          return i;
        }
        len = (strlen (str) * 5) / 8;
        buf = GNUNET_malloc (len);
        res = GNUNET_STRINGS_string_to_data (str,
                                             strlen (str),
                                             buf,
                                             len);
        if (GNUNET_OK != res)
        {
          GNUNET_free (buf);
          GNUNET_break_op (0);
          return i;
        }
        *spec[i].details.rsa_signature
          = GNUNET_CRYPTO_rsa_signature_decode (buf,
                                                len);
        GNUNET_free (buf);
        if (NULL == spec[i].details.rsa_signature)
          return i;
      }
      break;

    default:
      GNUNET_break (0);
      return i;
    }
  }
  return -1; /* all OK! */
}


/**
 * Free all elements allocated during a
 * #MAJ_parse_json() operation.
 *
 * @param spec specification of the parse operation
 * @param end number of elements in @a spec to process
 */
static void
parse_free (struct MAJ_Specification *spec,
            int end)
{
  int i;

  for (i=0;i<end;i++)
  {
    switch (spec[i].cmd)
    {
    case MAJ_CMD_END:
      GNUNET_assert (0);
      return;
    case MAJ_CMD_AMOUNT:
      break;
    case MAJ_CMD_TIME_ABSOLUTE:
      break;
    case MAJ_CMD_BINARY_FIXED:
      break;
    case MAJ_CMD_BINARY_VARIABLE:
      GNUNET_free (*spec[i].details.variable_data.dest_p);
      *spec[i].details.variable_data.dest_p = NULL;
      *spec[i].details.variable_data.dest_len_p = 0;
      break;
    case MAJ_CMD_RSA_PUBLIC_KEY:
      GNUNET_CRYPTO_rsa_public_key_free (*spec[i].details.rsa_public_key);
      *spec[i].details.rsa_public_key = NULL;
      break;
    case MAJ_CMD_RSA_SIGNATURE:
      GNUNET_CRYPTO_rsa_signature_free (*spec[i].details.rsa_signature);
      *spec[i].details.rsa_signature = NULL;
      break;
    default:
      GNUNET_break (0);
      break;
    }
  }
}


/**
 * Navigate and parse data in a JSON tree.
 *
 * @param root the JSON node to start the navigation at.
 * @param spec parse specification array
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
MAJ_parse_json (const json_t *root,
                struct MAJ_Specification *spec)
{
  int ret;

  ret = parse_json ((json_t *) root,
                    spec);
  if (-1 == ret)
    return GNUNET_OK;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "JSON field `%s` had unexpected value\n",
              spec[ret].field);
  parse_free (spec, ret);
  return GNUNET_SYSERR;
}


/**
 * Free all elements allocated during a
 * #MAJ_parse_json() operation.
 *
 * @param spec specification of the parse operation
 */
void
MAJ_parse_free (struct MAJ_Specification *spec)
{
  int i;

  for (i=0;MAJ_CMD_END != spec[i].cmd;i++) ;
  parse_free (spec, i);
}



/* end of mint_api_json.c */
