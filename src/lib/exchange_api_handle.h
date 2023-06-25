/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Taler Systems SA

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
 * @file lib/exchange_api_handle.h
 * @brief Internal interface to the handle part of the exchange's HTTP API
 * @author Christian Grothoff
 */
#ifndef EXCHANGE_API_HANDLE_H
#define EXCHANGE_API_HANDLE_H

#include <gnunet/gnunet_curl_lib.h>
#include "taler_auditor_service.h"
#include "taler_exchange_service.h"
#include "taler_util.h"
#include "taler_curl_lib.h"

/**
 * Entry in DLL of auditors used by an exchange.
 */
struct TEAH_AuditorListEntry;


/**
 * Stages of initialization for the `struct TALER_EXCHANGE_Handle`
 */
enum ExchangeHandleState
{
  /**
   * Just allocated.
   */
  MHS_INIT = 0,

  /**
   * Obtained the exchange's certification data and keys.
   */
  MHS_CERT = 1,

  /**
   * Failed to initialize (fatal).
   */
  MHS_FAILED = 2
};


/**
 * Handle to the exchange
 */
struct TALER_EXCHANGE_Handle
{
  /**
   * The context of this handle
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * The URL of the exchange (i.e. "http://exchange.taler.net/")
   */
  char *url;

  /**
   * Function to call with the exchange's certification data,
   * NULL if this has already been done.
   */
  TALER_EXCHANGE_CertificationCallback cert_cb;

  /**
   * Closure to pass to @e cert_cb.
   */
  void *cert_cb_cls;

  /**
   * Data for the request to get the /keys of a exchange,
   * NULL once we are past stage #MHS_INIT.
   */
  struct KeysRequest *kr;

  /**
   * Task for retrying /keys request.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * Raw key data of the exchange, only valid if
   * @e handshake_complete is past stage #MHS_CERT.
   */
  json_t *key_data_raw;

  /**
   * Head of DLL of auditors of this exchange.
   */
  struct TEAH_AuditorListEntry *auditors_head;

  /**
   * Tail of DLL of auditors of this exchange.
   */
  struct TEAH_AuditorListEntry *auditors_tail;

  /**
   * Key data of the exchange, only valid if
   * @e handshake_complete is past stage #MHS_CERT.
   */
  struct TALER_EXCHANGE_Keys key_data;

  /**
   * Retry /keys frequency.
   */
  struct GNUNET_TIME_Relative retry_delay;

  /**
   * When does @e key_data expire?
   */
  struct GNUNET_TIME_Timestamp key_data_expiration;

  /**
   * Number of subsequent failed requests to /keys.
   *
   * Used to compute the CURL timeout for the request.
   */
  unsigned int keys_error_count;

  /**
   * Number of subsequent failed requests to /wire.
   *
   * Used to compute the CURL timeout for the request.
   */
  unsigned int wire_error_count;

  /**
   * Stage of the exchange's initialization routines.
   */
  enum ExchangeHandleState state;

};


/**
 * Function called for each auditor to give us a chance to possibly
 * launch a deposit confirmation interaction.
 *
 * @param cls closure
 * @param auditor_url base URL of the auditor
 * @param auditor_pub public key of the auditor
 */
typedef void
(*TEAH_AuditorCallback)(void *cls,
                        const char *auditor_url,
                        const struct TALER_AuditorPublicKeyP *auditor_pub);


/**
 * Iterate over all available auditors for @a h, calling
 * @a ac and giving it a chance to start a deposit
 * confirmation interaction.
 *
 * @param keys the keys to go over auditors for
 * @param ac function to call per auditor
 * @param ac_cls closure for @a ac
 */
void
TEAH_get_auditors_for_dc (struct TALER_EXCHANGE_Keys *keys,
                          TEAH_AuditorCallback ac,
                          void *ac_cls);


/**
 * Get the context of a exchange.
 *
 * @param h the exchange handle to query
 * @return ctx context to execute jobs in
 */
struct GNUNET_CURL_Context *
TEAH_handle_to_context (struct TALER_EXCHANGE_Handle *h);


/**
 * Check if the handle is ready to process requests.
 *
 * @param h the exchange handle to query
 * @return #GNUNET_YES if we are ready, #GNUNET_NO if not
 */
enum GNUNET_GenericReturnValue
TEAH_handle_is_ready (struct TALER_EXCHANGE_Handle *h);

/**
 * Check if the handle is ready to process requests.
 *
 * @param h the exchange handle to query
 * @return #GNUNET_YES if we are ready, #GNUNET_NO if not
 */
enum GNUNET_GenericReturnValue
TEAH_handle_is_ready (struct TALER_EXCHANGE_Handle *h);


/**
 * Obtain the URL to use for an API request.
 *
 * @param h the exchange handle to query
 * @param path Taler API path (i.e. "/reserve/withdraw")
 * @return the full URL to use with cURL
 */
char *
TEAH_path_to_url (struct TALER_EXCHANGE_Handle *h,
                  const char *path);

/* end of exchange_api_handle.h */
#endif
