/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_aml-measures-get.c
 * @brief Return summary information about KYC measures
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_aml-measures-get.h"


MHD_RESULT
TEH_handler_aml_measures_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[])
{
  static json_t *roots;
  static json_t *programs;
  static json_t *checks;

  if (NULL == roots)
  {
    TALER_KYCLOGIC_get_measure_configuration (&roots,
                                              &programs,
                                              &checks);
  }
  if (NULL != args[0])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
      rc->url);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_object_incref ("roots",
                                    roots),
    GNUNET_JSON_pack_object_incref ("programs",
                                    programs),
    GNUNET_JSON_pack_object_incref ("checks",
                                    checks));
}


/* end of taler-exchange-httpd_aml-measures_get.c */
