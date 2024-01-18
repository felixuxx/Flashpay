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
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/auditor_api_get_config.c
 * @brief Implementation of /config for the auditor's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_auditor_service.h"
#include "taler_signatures.h"
#include "auditor_api_curl_defaults.h"


/**
 * Which revision of the Taler auditor protocol is implemented
 * by this library?  Used to determine compatibility.
 */
#define TALER_PROTOCOL_CURRENT 1

/**
 * How many revisions back are we compatible to?
 */
#define TALER_PROTOCOL_AGE 0


/**
 * Log error related to CURL operations.
 *
 * @param type log level
 * @param function which function failed to run
 * @param code what was the curl error code
 */
#define CURL_STRERROR(type, function, code)      \
  GNUNET_log (type, "Curl function `%s' has failed at `%s:%d' with error: %s", \
              function, __FILE__, __LINE__, curl_easy_strerror (code));


/**
 * Handle for the get config request.
 */
struct TALER_AUDITOR_GetConfigHandle
{
  /**
   * The context of this handle
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * Function to call with the auditor's certification data,
   * NULL if this has already been done.
   */
  TALER_AUDITOR_ConfigCallback config_cb;

  /**
   * Closure to pass to @e config_cb.
   */
  void *config_cb_cls;

  /**
   * Data for the request to get the /config of a auditor,
   * NULL once we are past stage #MHS_INIT.
   */
  struct GNUNET_CURL_Job *vr;

  /**
   * The url for the @e vr job.
   */
  char *vr_url;

};


/* ***************** Internal /config fetching ************* */

/**
 * Decode the JSON in @a resp_obj from the /config response and store the data
 * in the @a key_data.
 *
 * @param[in] resp_obj JSON object to parse
 * @param[in,out] vi where to store the results we decoded
 * @param[out] vc where to store config compatibility data
 * @return #TALER_EC_NONE on success
 */
static enum TALER_ErrorCode
decode_config_json (const json_t *resp_obj,
                    struct TALER_AUDITOR_ConfigInformation *vi,
                    enum TALER_AUDITOR_VersionCompatibility *vc)
{
  struct TALER_JSON_ProtocolVersion pv;
  const char *ver;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_version ("version",
                             &pv),
    GNUNET_JSON_spec_string ("version",
                             &ver),
    GNUNET_JSON_spec_fixed_auto ("exchange_master_public_key",
                                 &vi->exchange_master_public_key),
    GNUNET_JSON_spec_fixed_auto ("auditor_public_key",
                                 &vi->auditor_pub),
    GNUNET_JSON_spec_end ()
  };

  if (JSON_OBJECT != json_typeof (resp_obj))
  {
    GNUNET_break_op (0);
    return TALER_EC_GENERIC_JSON_INVALID;
  }
  /* check the config */
  if (GNUNET_OK !=
      GNUNET_JSON_parse (resp_obj,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return TALER_EC_GENERIC_JSON_INVALID;
  }
  vi->version = ver;
  *vc = TALER_AUDITOR_VC_MATCH;
  if (TALER_PROTOCOL_CURRENT < pv.current)
  {
    *vc |= TALER_AUDITOR_VC_NEWER;
    if (TALER_PROTOCOL_CURRENT < pv.current - pv.age)
      *vc |= TALER_AUDITOR_VC_INCOMPATIBLE;
  }
  if (TALER_PROTOCOL_CURRENT > pv.current)
  {
    *vc |= TALER_AUDITOR_VC_OLDER;
    if (TALER_PROTOCOL_CURRENT - TALER_PROTOCOL_AGE > pv.current)
      *vc |= TALER_AUDITOR_VC_INCOMPATIBLE;
  }
  return TALER_EC_NONE;
}


/**
 * Callback used when downloading the reply to a /config request
 * is complete.
 *
 * @param cls the `struct TALER_AUDITOR_GetConfigHandle`
 * @param response_code HTTP response code, 0 on error
 * @param gresp_obj parsed JSON result, NULL on error, must be a `const json_t *`
 */
static void
config_completed_cb (void *cls,
                     long response_code,
                     const void *gresp_obj)
{
  struct TALER_AUDITOR_GetConfigHandle *auditor = cls;
  const json_t *resp_obj = gresp_obj;
  struct TALER_AUDITOR_ConfigResponse vr = {
    .hr.reply = resp_obj,
    .hr.http_status = (unsigned int) response_code
  };

  auditor->vr = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Received config from URL `%s' with status %ld.\n",
              auditor->vr_url,
              response_code);
  switch (response_code)
  {
  case 0:
    GNUNET_break_op (0);
    vr.hr.ec = TALER_EC_INVALID;
    break;
  case MHD_HTTP_OK:
    if (NULL == resp_obj)
    {
      GNUNET_break_op (0);
      vr.hr.http_status = 0;
      vr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      break;
    }
    vr.hr.ec = decode_config_json (resp_obj,
                                   &vr.details.ok.vi,
                                   &vr.details.ok.compat);
    if (TALER_EC_NONE != vr.hr.ec)
    {
      GNUNET_break_op (0);
      vr.hr.http_status = 0;
      break;
    }
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    vr.hr.ec = TALER_JSON_get_error_code (resp_obj);
    vr.hr.hint = TALER_JSON_get_error_hint (resp_obj);
    break;
  default:
    vr.hr.ec = TALER_JSON_get_error_code (resp_obj);
    vr.hr.hint = TALER_JSON_get_error_hint (resp_obj);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) vr.hr.ec);
    break;
  }
  auditor->config_cb (auditor->config_cb_cls,
                      &vr);
  TALER_AUDITOR_get_config_cancel (auditor);
}


struct TALER_AUDITOR_GetConfigHandle *
TALER_AUDITOR_get_config (struct GNUNET_CURL_Context *ctx,
                          const char *url,
                          TALER_AUDITOR_ConfigCallback config_cb,
                          void *config_cb_cls)
{
  struct TALER_AUDITOR_GetConfigHandle *auditor;
  CURL *eh;

  auditor = GNUNET_new (struct TALER_AUDITOR_GetConfigHandle);
  auditor->config_cb = config_cb;
  auditor->config_cb_cls = config_cb_cls;
  auditor->ctx = ctx;
  auditor->vr_url = TALER_url_join (url,
                                    "config",
                                    NULL);
  if (NULL == auditor->vr_url)
  {
    GNUNET_break (0);
    GNUNET_free (auditor);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting auditor config with URL `%s'.\n",
              auditor->vr_url);
  eh = TALER_AUDITOR_curl_easy_get_ (auditor->vr_url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    TALER_AUDITOR_get_config_cancel (auditor);
    return NULL;
  }
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_TIMEOUT,
                                  (long) 300));
  auditor->vr = GNUNET_CURL_job_add (auditor->ctx,
                                     eh,
                                     &config_completed_cb,
                                     auditor);
  return auditor;
}


void
TALER_AUDITOR_get_config_cancel (struct TALER_AUDITOR_GetConfigHandle *auditor)
{
  if (NULL != auditor->vr)
  {
    GNUNET_CURL_job_cancel (auditor->vr);
    auditor->vr = NULL;
  }
  GNUNET_free (auditor->vr_url);
  GNUNET_free (auditor);
}


/* end of auditor_api_get_config.c */
