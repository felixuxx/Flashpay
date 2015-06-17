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
 * @file mint-lib/mint_api_context.h
 * @brief Internal interface to the context part of the mint's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "taler_signatures.h"


/**
 * Entry in the context's job queue.
 */
struct MAC_Job;

/**
 * Function to call upon completion of a job.
 */
typedef void
(*MAC_JobCompletionCallback)(void *cls);


/**
 * Schedule a CURL request to be executed and call the given @a jcc
 * upon its completion. Note that the context will make use of the
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
             void *jcc_cls);


/**
 * Obtain the `jcc_cls` argument from an `eh` that was
 * given to #MAC_job_add().
 *
 * @param eh easy handle that was used
 * @return the `jcc_cls` that was given to #MAC_job_add().
 */
void *
MAC_easy_to_closure (CURL *eh);


/**
 * Cancel a job.  Must only be called before the job completion
 * callback is called for the respective job.
 *
 * @param job job to cancel
 */
void
MAC_job_cancel (struct MAC_Job *job);


/* end of mint_api_context.h */
