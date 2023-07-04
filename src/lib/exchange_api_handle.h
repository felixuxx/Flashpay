/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2023 Taler Systems SA

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
 * Function called for each auditor to give us a chance to possibly
 * launch a deposit confirmation interaction.
 *
 * @param cls closure
 * @param auditor_url base URL of the auditor
 * @param auditor_pub public key of the auditor
 */
typedef void
(*TEAH_AuditorCallback)(
  void *cls,
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
TEAH_get_auditors_for_dc (
  struct TALER_EXCHANGE_Keys *keys,
  TEAH_AuditorCallback ac,
  void *ac_cls);


/* end of exchange_api_handle.h */
#endif
