/*
  This file is part of TALER
  Copyright (C) 2015 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd_wire.c
 * @brief Handle /wire requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler-mint-httpd_keystate.h"
#include "taler-mint-httpd_responses.h"
#include "taler-mint-httpd_wire.h"
#include <jansson.h>

/**
 * Handle a "/wire" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_WIRE_handler_wire (struct TMH_RequestHandler *rh,
                       struct MHD_Connection *connection,
                       void **connection_cls,
                       const char *upload_data,
                       size_t *upload_data_size)
{
  struct TALER_MintWireSupportMethodsPS wsm;
  struct TALER_MintPublicKeyP pub;
  struct TALER_MintSignatureP sig;
  json_t *methods;
  struct GNUNET_HashContext *hc;
  unsigned int i;
  const char *wf;

  methods = json_array ();
  hc = GNUNET_CRYPTO_hash_context_start ();
  for (i=0;NULL != (wf = TMH_expected_wire_formats[i]); i++)
  {
    json_array_append_new (methods,
                           json_string (wf));
    GNUNET_CRYPTO_hash_context_read (hc,
                                     wf,
                                     strlen (wf) + 1);
  }
  wsm.purpose.size = htonl (sizeof (wsm));
  wsm.purpose.purpose = htonl (TALER_SIGNATURE_MINT_WIRE_TYPES);
  GNUNET_CRYPTO_hash_context_finish (hc,
                                     &wsm.h_wire_types);
  TMH_KS_sign (&wsm.purpose,
               &pub,
               &sig);
  /* NOTE: for now, we only support *ONE* wire format per
     mint instance; if we supply multiple, we need to
     add the strings for each type separately here -- and
     hash the 0-terminated strings above differently as well...
     See #3972. */
  return TMH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o, s:o, s:o}",
                                       "methods", methods,
                                       "sig", TALER_json_from_data (&sig,
                                                                    sizeof (sig)),
                                       "pub", TALER_json_from_data (&pub,
                                                                    sizeof (pub)));
}


/**
 * Handle a "/wire/test" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_WIRE_handler_wire_test (struct TMH_RequestHandler *rh,
                            struct MHD_Connection *connection,
                            void **connection_cls,
                            const char *upload_data,
                            size_t *upload_data_size)
{
  struct MHD_Response *response;
  int ret;
  char *wire_test_redirect;
  unsigned int i;

  response = MHD_create_response_from_buffer (0, NULL,
                                              MHD_RESPMEM_PERSISTENT);
  if (NULL == response)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  for (i=0;NULL != TMH_expected_wire_formats[i];i++)
    if (0 == strcasecmp ("test",
                         TMH_expected_wire_formats[i]))
      break;
  if (NULL == TMH_expected_wire_formats[i])
  {
    /* Return 501: not implemented */
    ret = MHD_queue_response (connection,
			      MHD_HTTP_NOT_IMPLEMENTED,
			      response);
    MHD_destroy_response (response);
    return ret;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
					     "mint-wire-test",
					     "REDIRECT_URL",
					     &wire_test_redirect))
  {
    /* oopsie, configuration error */
    return TMH_RESPONSE_reply_internal_error (connection,
					      "REDIRECT_URL not configured");
  }
  MHD_add_response_header (response,
                           MHD_HTTP_HEADER_LOCATION,
                           wire_test_redirect);
  GNUNET_free (wire_test_redirect);
  ret = MHD_queue_response (connection,
                            rh->response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
}


/**
 * Handle a "/wire/sepa" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_WIRE_handler_wire_sepa (struct TMH_RequestHandler *rh,
			    struct MHD_Connection *connection,
			    void **connection_cls,
			    const char *upload_data,
			    size_t *upload_data_size)
{
  struct MHD_Response *response;
  int ret;
  char *sepa_wire_file;
  int fd;
  struct stat sbuf;
  unsigned int i;

  for (i=0;NULL != TMH_expected_wire_formats[i];i++)
    if (0 == strcasecmp ("sepa",
                         TMH_expected_wire_formats[i]))
      break;
  if (NULL == TMH_expected_wire_formats[i])
  {
    /* Return 501: not implemented */
    response = MHD_create_response_from_buffer (0, NULL,
                                                MHD_RESPMEM_PERSISTENT);
    if (NULL == response)
    {
      GNUNET_break (0);
      return MHD_NO;
    }
    ret = MHD_queue_response (connection,
			      MHD_HTTP_NOT_IMPLEMENTED,
			      response);
    MHD_destroy_response (response);
    return ret;
  }
  /* Fetch reply */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "mint-wire-sepa",
                                               "SEPA_RESPONSE_FILE",
                                               &sepa_wire_file))
  {
    return TMH_RESPONSE_reply_internal_error (connection,
					      "SEPA_RESPONSE_FILE not configured");
  }
  fd = open (sepa_wire_file,
	     O_RDONLY);
  if (-1 == fd)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
			      "open",
			      sepa_wire_file);
    GNUNET_free (sepa_wire_file);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to open SEPA_RESPONSE_FILE");
  }
  if (0 != fstat (fd, &sbuf))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
			      "fstat",
			      sepa_wire_file);
    (void) close (fd);
    GNUNET_free (sepa_wire_file);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to open SEPA_RESPONSE_FILE");
  }
  response = MHD_create_response_from_fd ((size_t) sbuf.st_size,
					  fd);
  GNUNET_free (sepa_wire_file);
  if (NULL == response)
  {
    (void) close (fd);
    GNUNET_break (0);
    return MHD_NO;
  }
  if (NULL != rh->mime_type)
    (void) MHD_add_response_header (response,
                                    MHD_HTTP_HEADER_CONTENT_TYPE,
                                    rh->mime_type);
  ret = MHD_queue_response (connection,
                            rh->response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
}

/* end of taler-mint-httpd_wire.c */
