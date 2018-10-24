/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
 * @file include/taler_auditor_service.h
 * @brief C interface of libtalerauditor, a C library to use auditor's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#ifndef _TALER_AUDITOR_SERVICE_H
#define _TALER_AUDITOR_SERVICE_H

#include <jansson.h>
#include "taler_util.h"
#include "taler_error_codes.h"
#include <gnunet/gnunet_curl_lib.h>


/* *********************  /version *********************** */

/**
 * @brief Information we get from the auditor about auditors.
 */
struct TALER_AUDITOR_VersionInformation
{
  /**
   * Public key of the auditing institution.  Wallets and merchants
   * are expected to be configured with a set of public keys of
   * auditors that they deem acceptable.  These public keys are
   * the roots of the Taler PKI.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * Supported Taler protocol version by the auditor.
   * String in the format current:revision:age using the
   * semantics of GNU libtool.  See
   * https://www.gnu.org/software/libtool/manual/html_node/Versioning.html#Versioning
   */
  char *version;

};


/**
 * How compatible are the protocol version of the auditor and this
 * client?  The bits (1,2,4) can be used to test if the auditor's
 * version is incompatible, older or newer respectively.
 */
enum TALER_AUDITOR_VersionCompatibility
{

  /**
   * The auditor runs exactly the same protocol version.
   */
  TALER_AUDITOR_VC_MATCH = 0,

  /**
   * The auditor is too old or too new to be compatible with this
   * implementation (bit)
   */
  TALER_AUDITOR_VC_INCOMPATIBLE = 1,

  /**
   * The auditor is older than this implementation (bit)
   */
  TALER_AUDITOR_VC_OLDER = 2,

  /**
   * The auditor is too old to be compatible with
   * this implementation.
   */
  TALER_AUDITOR_VC_INCOMPATIBLE_OUTDATED
  = TALER_AUDITOR_VC_INCOMPATIBLE
  | TALER_AUDITOR_VC_OLDER,

  /**
   * The auditor is more recent than this implementation (bit).
   */
  TALER_AUDITOR_VC_NEWER = 4,

  /**
   * The auditor is too recent for this implementation.
   */
  TALER_AUDITOR_VC_INCOMPATIBLE_NEWER
  = TALER_AUDITOR_VC_INCOMPATIBLE
  | TALER_AUDITOR_VC_NEWER,

  /**
   * We could not even parse the version data.
   */
  TALER_AUDITOR_VC_PROTOCOL_ERROR = 8

};


/**
 * Function called with information about the auditor.
 *
 * @param cls closure
 * @param vi basic information about the auditor
 * @param compat protocol compatibility information
 */
typedef void
(*TALER_AUDITOR_VersionCallback) (void *cls,
                                  const struct TALER_AUDITOR_VersionInformation *vi,
                                  enum TALER_AUDITOR_VersionCompatibility compat);


/**
 * @brief Handle to the auditor.  This is where we interact with
 * a particular auditor and keep the per-auditor information.
 */
struct TALER_AUDITOR_Handle;


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
 * @param version_cb function to call with the auditor's versionification information
 * @param version_cb_cls closure for @a version_cb
 * @return the auditor handle; NULL upon error
 */
struct TALER_AUDITOR_Handle *
TALER_AUDITOR_connect (struct GNUNET_CURL_Context *ctx,
		       const char *url,
		       TALER_AUDITOR_VersionCallback version_cb,
		       void *version_cb_cls);


/**
 * Disconnect from the auditor.
 *
 * @param auditor the auditor handle
 */
void
TALER_AUDITOR_disconnect (struct TALER_AUDITOR_Handle *auditor);


#endif  /* _TALER_AUDITOR_SERVICE_H */
