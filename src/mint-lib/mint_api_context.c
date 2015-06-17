/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file mint-lib/mint_api_context.c
 * @brief Implementation of the context part of the mint's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include "taler_mint_service.h"
#include "mint_api_context.h"


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
 * Failsafe flag. Raised if our constructor fails to initialize
 * the Curl library.
 */
static int TALER_MINT_curl_fail;


/**
 * Jobs are CURL requests running within a `struct TALER_MINT_Context`.
 */
struct MAC_Job
{

  /**
   * We keep jobs in a DLL.
   */
  struct MAC_Job *next;

  /**
   * We keep jobs in a DLL.
   */
  struct MAC_Job *prev;

  /**
   * Easy handle of the job.
   */
  CURL *easy_handle;

  /**
   * Context this job runs in.
   */
  struct TALER_MINT_Context *ctx;

  /**
   * Function to call upon completion.
   */
  MAC_JobCompletionCallback jcc;

  /**
   * Closure for @e jcc.
   */
  void *jcc_cls;

};


/**
 * Context
 */
struct TALER_MINT_Context
{
  /**
   * Curl multi handle
   */
  CURLM *multi;

  /**
   * Curl share handle
   */
  CURLSH *share;

  /**
   * We keep jobs in a DLL.
   */
  struct MAC_Job *jobs_head;

  /**
   * We keep jobs in a DLL.
   */
  struct MAC_Job *jobs_tail;

};


/**
 * Initialise this library.  This function should be called before using any of
 * the following functions.
 *
 * @return library context
 */
struct TALER_MINT_Context *
TALER_MINT_init ()
{
  struct TALER_MINT_Context *ctx;
  CURLM *multi;
  CURLSH *share;

  if (TALER_MINT_curl_fail)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Curl was not initialised properly\n");
    return NULL;
  }
  if (NULL == (multi = curl_multi_init ()))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to create a Curl multi handle\n");
    return NULL;
  }
  if (NULL == (share = curl_share_init ()))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to create a Curl share handle\n");
    return NULL;
  }
  ctx = GNUNET_new (struct TALER_MINT_Context);
  ctx->multi = multi;
  ctx->share = share;
  return ctx;
}


/**
 * Schedule a CURL request to be executed and call the given @a jcc
 * upon its completion.  Note that the context will make use of the
 * CURLOPT_PRIVATE facility of the CURL @a eh.  Applications can
 * instead use #MAC_easy_to_closure to extract the @a jcc_cls argument
 * from a valid @a eh afterwards.
 *
 * @param ctx context to execute the job in
 * @param eh curl easy handle for the request, will
 *           be executed AND cleaned up
 * @param jcc callback to invoke upon completion
 * @param jcc_cls closure for @a jcc
 */
struct MAC_Job *
MAC_job_add (struct TALER_MINT_Context *ctx,
             CURL *eh,
             MAC_JobCompletionCallback jcc,
             void *jcc_cls)
{
  struct MAC_Job *job;

  job = GNUNET_new (struct MAC_Job);
  job->easy_handle = eh;
  job->ctx = ctx;
  job->jcc = jcc;
  job->jcc_cls = jcc_cls;
  GNUNET_CONTAINER_DLL_insert (ctx->jobs_head,
                               ctx->jobs_tail,
                               job);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_PRIVATE,
                                   job));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_SHARE,
                                   ctx->share));
  GNUNET_assert (CURLM_OK ==
                 curl_multi_add_handle (ctx->multi,
                                        eh));
  return job;
}


/**
 * Obtain the `jcc_cls` argument from an `eh` that was
 * given to #MAC_job_add().
 *
 * @param eh easy handle that was used
 * @return the `jcc_cls` that was given to #MAC_job_add().
 */
void *
MAC_easy_to_closure (CURL *eh)
{
  struct MAC_Job *job;

  GNUNET_assert (CURLE_OK ==
                 curl_easy_getinfo (eh,
                                    CURLINFO_PRIVATE,
                                    (char *) &job));
  return job->jcc_cls;
}


/**
 * Cancel a job.  Must only be called before the job completion
 * callback is called for the respective job.
 *
 * @param job job to cancel
 */
void
MAC_job_cancel (struct MAC_Job *job)
{
  struct TALER_MINT_Context *ctx = job->ctx;

  GNUNET_CONTAINER_DLL_remove (ctx->jobs_head,
                               ctx->jobs_tail,
                               job);
  GNUNET_assert (CURLM_OK ==
                 curl_multi_remove_handle (ctx->multi,
                                           job->easy_handle));
  curl_easy_cleanup (job->easy_handle);
  GNUNET_free (job);
}


/**
 * Run the main event loop for the Taler interaction.
 *
 * @param ctx the library context
 */
void
TALER_MINT_perform (struct TALER_MINT_Context *ctx)
{
  CURLMsg *cmsg;
  struct MAC_Job *job;
  int n_running;
  int n_completed;

  (void) curl_multi_perform (ctx->multi,
                             &n_running);
  while (NULL != (cmsg = curl_multi_info_read (ctx->multi,
                                               &n_completed)))
  {
    /* Only documented return value is CURLMSG_DONE */
    GNUNET_break (CURLMSG_DONE == cmsg->msg);
    GNUNET_assert (CURLE_OK ==
                   curl_easy_getinfo (cmsg->easy_handle,
                                      CURLINFO_PRIVATE,
                                      (char *) &job));
    GNUNET_assert (job->ctx == ctx);
    job->jcc (job->jcc_cls);
    MAC_job_cancel (job);
  }
}


/**
 * Obtain the information for a select() call to wait until
 * #TALER_MINT_perform() is ready again.  Note that calling
 * any other TALER_MINT-API may also imply that the library
 * is again ready for #TALER_MINT_perform().
 *
 * Basically, a client should use this API to prepare for select(),
 * then block on select(), then call #TALER_MINT_perform() and then
 * start again until the work with the context is done.
 *
 * This function will NOT zero out the sets and assumes that @a max_fd
 * and @a timeout are already set to minimal applicable values.  It is
 * safe to give this API FD-sets and @a max_fd and @a timeout that are
 * already initialized to some other descriptors that need to go into
 * the select() call.
 *
 * @param ctx context to get the event loop information for
 * @param read_fd_set will be set for any pending read operations
 * @param write_fd_set will be set for any pending write operations
 * @param except_fd_set is here because curl_multi_fdset() has this argument
 * @param max_fd set to the highest FD included in any set;
 *        if the existing sets have no FDs in it, the initial
 *        value should be "-1". (Note that `max_fd + 1` will need
 *        to be passed to select().)
 * @param timeout set to the timeout in milliseconds (!); -1 means
 *        no timeout (NULL, blocking forever is OK), 0 means to
 *        proceed immediately with #TALER_MINT_perform().
 */
void
TALER_MINT_get_select_info (struct TALER_MINT_Context *ctx,
                            fd_set *read_fd_set,
                            fd_set *write_fd_set,
                            fd_set *except_fd_set,
                            int *max_fd,
                            long *timeout)
{
  GNUNET_assert (CURLM_OK ==
                 curl_multi_fdset (ctx->multi,
                                   read_fd_set,
                                   write_fd_set,
                                   except_fd_set,
                                   max_fd));
  GNUNET_assert (CURLM_OK ==
                 curl_multi_timeout (ctx->multi,
                                     timeout));
  if ( (-1 == (*timeout)) &&
       (NULL != ctx->jobs_head) )
    *timeout = 1000 * 60 * 5; /* curl is not always good about giving timeouts */
}


/**
 * Cleanup library initialisation resources.  This function should be called
 * after using this library to cleanup the resources occupied during library's
 * initialisation.
 *
 * @param ctx the library context
 */
void
TALER_MINT_fini (struct TALER_MINT_Context *ctx)
{
  /* all jobs must have been cancelled at this time, assert this */
  GNUNET_assert (NULL == ctx->jobs_head);
  curl_share_cleanup (ctx->share);
  curl_multi_cleanup (ctx->multi);
  GNUNET_free (ctx);
}


/**
 * Initial global setup logic, specifically runs the Curl setup.
 */
__attribute__ ((constructor))
void
TALER_MINT_constructor__ (void)
{
  CURLcode ret;

  if (CURLE_OK != (ret = curl_global_init (CURL_GLOBAL_DEFAULT)))
  {
    CURL_STRERROR (GNUNET_ERROR_TYPE_ERROR,
                   "curl_global_init",
                   ret);
    TALER_MINT_curl_fail = 1;
  }
}


/**
 * Cleans up after us, specifically runs the Curl cleanup.
 */
__attribute__ ((destructor))
void
TALER_MINT_destructor__ (void)
{
  if (TALER_MINT_curl_fail)
    return;
  curl_global_cleanup ();
}

/* end of mint_api_context.c */
