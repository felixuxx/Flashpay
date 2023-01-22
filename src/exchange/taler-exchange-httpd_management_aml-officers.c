/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file taler-exchange-httpd_management_aml-officers.c
 * @brief Handle request to update AML officer status
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"


/**
 * How often do we try the DB operation at most?
 */
#define MAX_RETRIES 10


MHD_RESULT
TEH_handler_management_aml_officers (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  const char *officer_name;
  struct GNUNET_TIME_Timestamp change_date;
  bool is_active;
  bool read_only;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("officer_pub",
                                 &officer_pub),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_bool ("is_active",
                           &is_active),
    GNUNET_JSON_spec_bool ("read_only",
                           &read_only),
    GNUNET_JSON_spec_string ("officer_name",
                             &officer_name),
    GNUNET_JSON_spec_timestamp ("change_date",
                                &change_date),
    GNUNET_JSON_spec_end ()
  };

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_exchange_offline_aml_officer_status_verify (
        &officer_pub,
        officer_name,
        change_date,
        is_active,
        read_only,
        &TEH_master_public_key,
        &master_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_UPDATE_AML_OFFICER_SIGNATURE_INVALID,
      NULL);
  }
  {
    enum GNUNET_DB_QueryStatus qs;
    struct GNUNET_TIME_Timestamp last_date;
    unsigned int retries_left = MAX_RETRIES;

    do {
      qs = TEH_plugin->insert_aml_officer (TEH_plugin->cls,
                                           &officer_pub,
                                           &master_sig,
                                           officer_name,
                                           is_active,
                                           read_only,
                                           change_date,
                                           &last_date);
      if (0 == --retries_left)
        break;
    } while (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (qs < 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_STORE_FAILED,
                                         "insert_aml_officer");
    }
    if (GNUNET_TIME_timestamp_cmp (last_date,
                                   >,
                                   change_date))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_EXCHANGE_MANAGEMENT_AML_OFFICERS_MORE_RECENT_PRESENT,
        NULL);
    }
  }
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_aml-officers.c */
