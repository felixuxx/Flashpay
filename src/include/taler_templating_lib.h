/*
  This file is part of TALER
  Copyright (C) 2020, 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler_templating_lib.h
 * @brief logic to load and complete HTML templates
 * @author Christian Grothoff
 */
#ifndef TALER_TEMPLATING_LIB_H
#define TALER_TEMPLATING_LIB_H

#include <microhttpd.h>
#include "taler_mhd_lib.h"

/**
 * Fill in Mustach template @a tmpl using the data from @a root
 * and return the result in @a result.
 *
 * @param tmpl 0-terminated string with Mustach template
 * @param root JSON data to fill into the template
 * @param[out] result where to write the result
 * @param[out] result_size where to write the length of the result
 * @return 0 on success, otherwise Mustach-specific error code
 */
int
TALER_TEMPLATING_fill (const char *tmpl,
                       const json_t *root,
                       void **result,
                       size_t *result_size);


/**
 * Load a @a template and substitute using @a root, returning the result in a
 * @a reply encoded suitable for the @a connection with the given @a
 * http_status code.  On errors, the @a http_status code
 * is updated to reflect the type of error encoded in the
 * @a reply.
 *
 * @param connection the connection we act upon
 * @param[in,out] http_status code to use on success,
 *           set to alternative code on failure
 * @param template basename of the template to load
 * @param instance_id instance ID, used to compute static files URL
 * @param taler_uri value for "Taler:" header to set, or NULL
 * @param root JSON object to pass as the root context
 * @param[out] reply where to write the response object
 * @return #GNUNET_OK on success (reply queued), #GNUNET_NO if an error was queued,
 *         #GNUNET_SYSERR on failure (to queue an error)
 */
enum GNUNET_GenericReturnValue
TALER_TEMPLATING_build (struct MHD_Connection *connection,
                        unsigned int *http_status,
                        const char *template,
                        const char *instance_id,
                        const char *taler_uri,
                        const json_t *root,
                        struct MHD_Response **reply);


/**
 * Load a @a template and substitute using @a root, returning
 * the result to the @a connection with the given
 * @a http_status code.
 *
 * @param connection the connection we act upon
 * @param http_status code to use on success
 * @param template basename of the template to load
 * @param instance_id instance ID, used to compute static files URL
 * @param taler_uri value for "Taler:" header to set, or NULL
 * @param root JSON object to pass as the root context
 * @return #GNUNET_OK on success (reply queued), #GNUNET_NO if an error was queued,
 *         #GNUNET_SYSERR on failure (to queue an error)
 */
enum GNUNET_GenericReturnValue
TALER_TEMPLATING_reply (struct MHD_Connection *connection,
                        unsigned int http_status,
                        const char *template,
                        const char *instance_id,
                        const char *taler_uri,
                        const json_t *root);


/**
 * Load a @a template and substitute an error message based on @a ec and @a
 * detail, returning the result to the @a connection with the given @a
 * http_status code.
 *
 * @param connection the connection we act upon
 * @param template_basename basename of the template to load
 * @param http_status code to use on success
 * @param ec error code to return
 * @param detail optional text to add to the template
 * @return #MHD_YES on success, #MHD_NO to just close the connection
 */
MHD_RESULT
TALER_TEMPLATING_reply_error (struct MHD_Connection *connection,
                              const char *template_basename,
                              unsigned int http_status,
                              enum TALER_ErrorCode ec,
                              const char *detail);

/**
 * Preload templates.
 *
 * @param subsystem name of the subsystem, "merchant" or "exchange"
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_TEMPLATING_init (const char *subsystem);


/**
 * Nicely shut down templating subsystem.
 */
void
TALER_TEMPLATING_done (void);

#endif
