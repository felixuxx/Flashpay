/*
  This file is part of TALER
  Copyright (C) 2014-2018 GNUnet e.V.

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
 * @file lib/auditor_api_handle.c
 * @brief Implementation of the "handle" component of the auditor's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_auditor_service.h"
#include "taler_signatures.h"
#include "auditor_api_handle.h"
#include "auditor_api_curl_defaults.h"
#include "backoff.h"

/**
 * Which revision of the Taler auditor protocol is implemented
 * by this library?  Used to determine compatibility.
 */
#define TALER_PROTOCOL_CURRENT 0

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
 * Stages of initialization for the `struct TALER_AUDITOR_Handle`
 */
enum AuditorHandleState
{
  /**
   * Just allocated.
   */
  MHS_INIT = 0,

  /**
   * Obtained the auditor's versioning data and version.
   */
  MHS_VERSION = 1,

  /**
   * Failed to initialize (fatal).
   */
  MHS_FAILED = 2
};


/**
 * Data for the request to get the /version of a auditor.
 */
struct VersionRequest;


/**
 * Handle to the auditor
 */
struct TALER_AUDITOR_Handle
{
  /**
   * The context of this handle
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * The URL of the auditor (i.e. "http://auditor.taler.net/")
   */
  char *url;

  /**
   * Function to call with the auditor's certification data,
   * NULL if this has already been done.
   */
  TALER_AUDITOR_VersionCallback version_cb;

  /**
   * Closure to pass to @e version_cb.
   */
  void *version_cb_cls;

  /**
   * Data for the request to get the /version of a auditor,
   * NULL once we are past stage #MHS_INIT.
   */
  struct VersionRequest *vr;

  /**
   * Task for retrying /version request.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * /version data of the auditor, only valid if
   * @e handshake_complete is past stage #MHS_VERSION.
   */
  struct TALER_AUDITOR_VersionInformation vi;

  /**
   * Retry /version frequency.
   */
  struct GNUNET_TIME_Relative retry_delay;

  /**
   * Stage of the auditor's initialization routines.
   */
  enum AuditorHandleState state;

};


/* ***************** Internal /version fetching ************* */

/**
 * Data for the request to get the /version of a auditor.
 */
struct VersionRequest
{
  /**
   * The connection to auditor this request handle will use
   */
  struct TALER_AUDITOR_Handle *auditor;

  /**
   * The url for this handle
   */
  char *url;

  /**
   * Entry for this request with the `struct GNUNET_CURL_Context`.
   */
  struct GNUNET_CURL_Job *job;

};


/**
 * Release memory occupied by a version request.
 * Note that this does not cancel the request
 * itself.
 *
 * @param vr request to free
 */
static void
free_version_request (struct VersionRequest *vr)
{
  GNUNET_free (vr->url);
  GNUNET_free (vr);
}


/**
 * Free version data object.
 *
 * @param vi data to free (pointer itself excluded)
 */
static void
free_version_info (struct TALER_AUDITOR_VersionInformation *vi)
{
  GNUNET_free_non_null (vi->version);
  vi->version = NULL;
}


/**
 * Decode the JSON in @a resp_obj from the /version response and store the data
 * in the @a key_data.
 *
 * @param[in] resp_obj JSON object to parse
 * @param check_sig #GNUNET_YES if we should check the signature
 * @param[out] vi where to store the results we decoded
 * @param[out] vc where to store version compatibility data
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error (malformed JSON)
 */
static int
decode_version_json (const json_t *resp_obj,
                     int check_sig,
                     struct TALER_AUDITOR_VersionInformation *vi,
                     enum TALER_AUDITOR_VersionCompatibility *vc)
{
  unsigned int age;
  unsigned int revision;
  unsigned int current;
  const char *ver;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("version",
			     &ver),
    GNUNET_JSON_spec_fixed_auto ("auditor_public_key",
				 &vi->auditor_pub),
    GNUNET_JSON_spec_end()
  };

  if (JSON_OBJECT != json_typeof (resp_obj))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* check the version */
  if (GNUNET_OK !=
      GNUNET_JSON_parse (resp_obj,
			 spec,
			 NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (3 != sscanf (ver,
		   "%u:%u:%u",
		   &current,
		   &revision,
		   &age))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  vi->version = GNUNET_strdup (ver);
  *vc = TALER_AUDITOR_VC_MATCH;
  if (TALER_PROTOCOL_CURRENT < current)
  {
    *vc |= TALER_AUDITOR_VC_NEWER;
    if (TALER_PROTOCOL_CURRENT < current - age)
      *vc |= TALER_AUDITOR_VC_INCOMPATIBLE;
  }
  if (TALER_PROTOCOL_CURRENT > current)
  {
    *vc |= TALER_AUDITOR_VC_OLDER;
    if (TALER_PROTOCOL_CURRENT - TALER_PROTOCOL_AGE > current)
      *vc |= TALER_AUDITOR_VC_INCOMPATIBLE;
  }
  return GNUNET_OK;
}

/**
 * Initiate download of /version from the auditor.
 *
 * @param cls auditor where to download /version from
 */
static void
request_version (void *cls);


/**
 * Callback used when downloading the reply to a /version request
 * is complete.
 *
 * @param cls the `struct VersionRequest`
 * @param response_code HTTP response code, 0 on error
 * @param resp_obj parsed JSON result, NULL on error
 */
static void
version_completed_cb (void *cls,
		      long response_code,
		      const void *gresp_obj)
{
  const json_t *resp_obj = gresp_obj;
  struct VersionRequest *vr = cls;
  struct TALER_AUDITOR_Handle *auditor = vr->auditor;
  enum TALER_AUDITOR_VersionCompatibility vc;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received version from URL `%s' with status %ld.\n",
              vr->url,
              response_code);
  vc = TALER_AUDITOR_VC_PROTOCOL_ERROR;
  switch (response_code)
  {
  case 0:
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    free_version_request (vr);
    auditor->vr = NULL;
    GNUNET_assert (NULL == auditor->retry_task);
    auditor->retry_delay = EXCHANGE_LIB_BACKOFF (auditor->retry_delay);
    auditor->retry_task = GNUNET_SCHEDULER_add_delayed (auditor->retry_delay,
                                                        &request_version,
                                                        auditor);
    return;
  case MHD_HTTP_OK:
    if (NULL == resp_obj)
    {
      GNUNET_break_op (0);
      TALER_LOG_WARNING ("NULL body for a 200-OK /version\n");
      response_code = 0;
      break;
    }
    if (GNUNET_OK !=
        decode_version_json (resp_obj,
                             GNUNET_YES,
                             &auditor->vi,
                             &vc))
    {
      GNUNET_break_op (0);
      response_code = 0;
      break;
    }
    auditor->retry_delay = GNUNET_TIME_UNIT_ZERO;
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    break;
  }
  if (MHD_HTTP_OK != response_code)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"/version failed for auditor %p: %u!\n",
		auditor,
		(unsigned int) response_code);
    auditor->vr = NULL;
    free_version_request (vr);
    auditor->state = MHS_FAILED;
    free_version_info (&auditor->vi);
    /* notify application that we failed */
    auditor->version_cb (auditor->version_cb_cls,
			 NULL,
			 vc);
    return;
  }

  auditor->vr = NULL;
  free_version_request (vr);
  TALER_LOG_DEBUG ("Switching auditor state to 'version'\n");
  auditor->state = MHS_VERSION;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Auditor %p is now READY!\n",
              auditor);
  /* notify application about the key information */
  auditor->version_cb (auditor->version_cb_cls,
                       &auditor->vi,
                       vc);
}


/* ********************* library internal API ********* */


/**
 * Get the context of a auditor.
 *
 * @param h the auditor handle to query
 * @return ctx context to execute jobs in
 */
struct GNUNET_CURL_Context *
MAH_handle_to_context (struct TALER_AUDITOR_Handle *h)
{
  return h->ctx;
}


/**
 * Check if the handle is ready to process requests.
 *
 * @param h the auditor handle to query
 * @return #GNUNET_YES if we are ready, #GNUNET_NO if not
 */
int
MAH_handle_is_ready (struct TALER_AUDITOR_Handle *h)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking if auditor %p is now ready: %s\n",
              h,
	      (MHD_VERSION == h->state) ? "yes" : "no");
  return (MHS_VERSION == h->state) ? GNUNET_YES : GNUNET_NO;
}


/**
 * Obtain the URL to use for an API request.
 *
 * @param h handle for the auditor
 * @param path Taler API path (i.e. "/deposit-confirmation")
 * @return the full URL to use with cURL
 */
char *
MAH_path_to_url (struct TALER_AUDITOR_Handle *h,
                 const char *path)
{
  return MAH_path_to_url2 (h->url,
                           path);
}


/**
 * Obtain the URL to use for an API request.
 *
 * @param base_url base URL of the auditor (i.e. "http://auditor/")
 * @param path Taler API path (i.e. "/deposit-confirmation")
 * @return the full URL to use with cURL
 */
char *
MAH_path_to_url2 (const char *base_url,
                  const char *path)
{
  char *url;

  if ( ('/' == path[0]) &&
       (0 < strlen (base_url)) &&
       ('/' == base_url[strlen (base_url) - 1]) )
    path++; /* avoid generating URL with "//" from concat */
  GNUNET_asprintf (&url,
                   "%s%s",
                   base_url,
                   path);
  return url;
}


/* ********************* public API ******************* */


/**
 * Initialise a connection to the auditor. Will connect to the
 * auditor and obtain information about the auditor's master public
 * key and the auditor's auditor.  The respective information will
 * be passed to the @a version_cb once available, and all future
 * interactions with the auditor will be checked to be signed
 * (where appropriate) by the respective master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the auditor
 * @param version_cb function to call with the
 *        auditor's version information
 * @param version_cb_cls closure for @a version_cb
 * @return the auditor handle; NULL upon error
 */
struct TALER_AUDITOR_Handle *
TALER_AUDITOR_connect (struct GNUNET_CURL_Context *ctx,
		       const char *url,
		       TALER_AUDITOR_VersionCallback version_cb,
		       void *version_cb_cls)
{
  struct TALER_AUDITOR_Handle *auditor;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Connecting to auditor at URL `%s'.\n",
              url);
  /* Disable 100 continue processing */
  GNUNET_break (GNUNET_OK ==
                GNUNET_CURL_append_header (ctx,
                                           "Expect:"));
#if COMPRESS_BODIES
  /* Tell auditor we compress bodies */
  GNUNET_break (GNUNET_OK ==
                GNUNET_CURL_append_header (ctx,
                                           "Content-Encoding: deflate"));
#endif
  auditor = GNUNET_new (struct TALER_AUDITOR_Handle);
  auditor->ctx = ctx;
  auditor->url = GNUNET_strdup (url);
  auditor->version_cb = version_cb;
  auditor->version_cb_cls = version_cb_cls;
  auditor->retry_task = GNUNET_SCHEDULER_add_now (&request_version,
						  auditor);
  return auditor;
}


/**
 * Initiate download of /version from the auditor.
 *
 * @param cls auditor where to download /version from
 */
static void
request_version (void *cls)
{
  struct TALER_AUDITOR_Handle *auditor = cls;
  struct VersionRequest *vr;
  CURL *eh;

  auditor->retry_task = NULL;
  GNUNET_assert (NULL == auditor->vr);
  vr = GNUNET_new (struct VersionRequest);
  vr->auditor = auditor;
  vr->url = MAH_path_to_url (auditor,
			     "/version");
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting auditor version with URL `%s'.\n",
              vr->url);
  eh = TAL_curl_easy_get (vr->url);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_TIMEOUT,
                                   (long) 300));
  vr->job = GNUNET_CURL_job_add (auditor->ctx,
                                 eh,
                                 GNUNET_NO,
                                 &version_completed_cb,
                                 vr);
  auditor->vr = vr;
}


/**
 * Disconnect from the auditor
 *
 * @param auditor the auditor handle
 */
void
TALER_AUDITOR_disconnect (struct TALER_AUDITOR_Handle *auditor)
{
  if (NULL != auditor->vr)
  {
    GNUNET_CURL_job_cancel (auditor->vr->job);
    free_version_request (auditor->vr);
    auditor->vr = NULL;
  }
  free_version_info (&auditor->vi);
  if (NULL != auditor->retry_task)
  {
    GNUNET_SCHEDULER_cancel (auditor->retry_task);
    auditor->retry_task = NULL;
  }
  GNUNET_free (auditor->url);
  GNUNET_free (auditor);
}


/* end of auditor_api_handle.c */
