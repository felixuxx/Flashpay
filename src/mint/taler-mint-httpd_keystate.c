/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

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
 * @file taler-mint-httpd_keystate.c
 * @brief management of our coin signing keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <pthread.h>
#include "taler_signatures.h"
#include "taler-mint-httpd_keystate.h"
#include "taler_util.h"
#include "taler-mint-httpd_parsing.h"


/**
 * Snapshot of the (coin and signing) keys (including private keys) of
 * the mint.  There can be multiple instances of this struct, as it is
 * reference counted and only destroyed once the last user is done
 * with it.  The current instance is acquired using
 * #TALER_MINT_key_state_acquire().  Using this function increases the
 * reference count.  The contents of this structure (except for the
 * reference counter) should be considered READ-ONLY until it is
 * ultimately destroyed (as there can be many concurrent users).
 */
struct MintKeyState
{
  /**
   * JSON array with denomination keys.  (Currently not really used
   * after initialization.)
   */
  json_t *denom_keys_array;

  /**
   * JSON array with signing keys. (Currently not really used
   * after initialization.)
   */
  json_t *sign_keys_array;

  /**
   * Cached JSON text that the mint will send for a "/keys" request.
   * Includes our @e master_pub public key, the signing and
   * denomination keys as well as the @e reload_time.
   */
  char *keys_json;

  /**
   * Mapping from denomination keys to denomination key issue struct.
   * Used to lookup the key by hash.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denomkey_map;

  /**
   * When did we initiate the key reloading?
   */
  struct GNUNET_TIME_Absolute reload_time;

  /**
   * When is the next key invalid and we have to reload? (We also
   * reload on SIGUSR1.)
   */
  struct GNUNET_TIME_Absolute next_reload;

  /**
   * Mint signing key that should be used currently.
   */
  struct TALER_MINT_SignKeyIssuePriv current_sign_key_issue;

  /**
   * Reference count.  The struct is released when the RC hits zero.
   */
  unsigned int refcnt;
};


/**
 * Mint key state.  Never use directly, instead access via
 * #TALER_MINT_key_state_acquire() and #TALER_MINT_key_state_release().
 */
static struct MintKeyState *internal_key_state;

/**
 * Mutex protecting access to #internal_key_state.
 */
static pthread_mutex_t internal_key_state_mutex = PTHREAD_MUTEX_INITIALIZER;

/**
 * Pipe used for signaling reloading of our key state.
 */
static int reload_pipe[2];


/**
 * Convert the public part of a denomination key issue to a JSON
 * object.
 *
 * @param dki the denomination key issue
 * @return a JSON object describing the denomination key isue (public part)
 */
static json_t *
denom_key_issue_to_json (const struct TALER_MINT_DenomKeyIssue *dki)
{
  return
    json_pack ("{s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o}",
               "master_sig",
               TALER_JSON_from_data (&dki->signature,
                                     sizeof (struct GNUNET_CRYPTO_EddsaSignature)),
               "stamp_start",
               TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (dki->start)),
               "stamp_expire_withdraw",
               TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (dki->expire_withdraw)),
               "stamp_expire_deposit",
               TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (dki->expire_spend)),
               "denom_pub",
               TALER_JSON_from_rsa_public_key (dki->denom_pub),
               "value",
               TALER_JSON_from_amount (TALER_amount_ntoh (dki->value)),
               "fee_withdraw",
               TALER_JSON_from_amount (TALER_amount_ntoh (dki->fee_withdraw)),
               "fee_deposit",
               TALER_JSON_from_amount (TALER_amount_ntoh (dki->fee_deposit)),
               "fee_refresh",
               TALER_JSON_from_amount (TALER_amount_ntoh (dki->fee_refresh)));
}


/**
 * Get the relative time value that describes how
 * far in the future do we want to provide coin keys.
 *
 * @return the provide duration
 */
static struct GNUNET_TIME_Relative
TALER_MINT_conf_duration_provide ()
{
  struct GNUNET_TIME_Relative rel;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "mint_keys",
                                           "lookahead_provide",
                                           &rel))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "mint_keys.lookahead_provide not valid or not given\n");
    GNUNET_assert (0);
  }
  return rel;
}


/**
 * Iterator for (re)loading/initializing denomination keys.
 *
 * @param cls closure
 * @param dki the denomination key issue
 * @param alias coin alias
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_keys_denom_iter (void *cls,
                        const char *alias,
                        const struct TALER_MINT_DenomKeyIssuePriv *dki)
{
  struct MintKeyState *ctx = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute horizon;
  struct GNUNET_HashCode denom_key_hash;
  struct TALER_MINT_DenomKeyIssuePriv *d2;
  int res;

  horizon = GNUNET_TIME_relative_to_absolute (TALER_MINT_conf_duration_provide ());
  if (GNUNET_TIME_absolute_ntoh (dki->issue.expire_spend).abs_value_us >
      horizon.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping future denomination key `%s'\n",
                alias);
    return GNUNET_OK;
  }
  now = GNUNET_TIME_absolute_get ();
  if (GNUNET_TIME_absolute_ntoh (dki->issue.expire_spend).abs_value_us <
      now.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping expired denomination key `%s'\n",
                alias);
    return GNUNET_OK;
  }

  GNUNET_CRYPTO_hash (&dki->issue.denom_pub,
                      sizeof (struct GNUNET_CRYPTO_EddsaPublicKey),
                      &denom_key_hash);
  d2 = GNUNET_memdup (dki,
                      sizeof (struct TALER_MINT_DenomKeyIssuePriv));
  res = GNUNET_CONTAINER_multihashmap_put (ctx->denomkey_map,
                                           &denom_key_hash,
                                           d2,
                                           GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY);
  if (GNUNET_OK != res)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Duplicate denomination key `%s'\n",
                alias);
    GNUNET_free (d2);
    return GNUNET_OK;
  }
  json_array_append_new (ctx->denom_keys_array,
                         denom_key_issue_to_json (&dki->issue));
  return GNUNET_OK;
}


/**
 * Convert the public part of a sign key issue to a JSON object.
 *
 * @param ski the sign key issue
 * @return a JSON object describing the sign key isue (public part)
 */
static json_t *
sign_key_issue_to_json (const struct TALER_MINT_SignKeyIssue *ski)
{
  return
    json_pack ("{s:o, s:o, s:o, s:o}",
               "stamp_start",
               TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (ski->start)),
               "stamp_expire",
               TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (ski->expire)),
               "master_sig",
               TALER_JSON_from_data (&ski->signature,
                                     sizeof (struct GNUNET_CRYPTO_EddsaSignature)),
               "key",
               TALER_JSON_from_data (&ski->signkey_pub,
                                     sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)));
}


/**
 * Iterator for sign keys.
 *
 * @param cls closure
 * @param filename name of the file the key came from
 * @param ski the sign key issue
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_keys_sign_iter (void *cls,
                       const char *filename,
                       const struct TALER_MINT_SignKeyIssuePriv *ski)
{
  struct MintKeyState *ctx = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute horizon;

  horizon = GNUNET_TIME_relative_to_absolute (TALER_MINT_conf_duration_provide ());
  if (GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us >
      horizon.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping future signing key `%s'\n",
                filename);
    return GNUNET_OK;
  }
  now = GNUNET_TIME_absolute_get ();
  if (GNUNET_TIME_absolute_ntoh (ski->issue.expire).abs_value_us <
      now.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping expired signing key `%s'\n",
                filename);
    return GNUNET_OK;
  }

  /* The signkey is valid at this time, check if it's more recent than
     what we have so far! */
  if (GNUNET_TIME_absolute_ntoh (ctx->current_sign_key_issue.issue.start).abs_value_us <
      GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us)
  {
    /* We keep the most recent one around */
    ctx->current_sign_key_issue = *ski;
  }
  json_array_append_new (ctx->sign_keys_array,
                         sign_key_issue_to_json (&ski->issue));

  return GNUNET_OK;
}


/**
 * Iterator for freeing denomination keys.
 *
 * @param cls closure with the `struct MintKeyState`
 * @param key key for the denomination key
 * @param alias coin alias
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
free_denom_key (void *cls,
                const struct GNUNET_HashCode *key,
                void *value)
{
  struct TALER_MINT_DenomKeyIssuePriv *dki = value;

  GNUNET_free (dki);
  return GNUNET_OK;
}


/**
 * Release key state, free if necessary (if reference count gets to zero).
 *
 * @param key_state the key state to release
 */
void
TALER_MINT_key_state_release (struct MintKeyState *key_state)
{
  GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
  GNUNET_assert (0 < key_state->refcnt);
  key_state->refcnt--;
  if (0 == key_state->refcnt)
  {
    json_decref (key_state->denom_keys_array);
    json_decref (key_state->sign_keys_array);
    GNUNET_CONTAINER_multihashmap_iterate (key_state->denomkey_map,
                                           &free_denom_key,
                                           key_state);
    GNUNET_CONTAINER_multihashmap_destroy (key_state->denomkey_map);
    GNUNET_free (key_state->keys_json);
    GNUNET_free (key_state);
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
}


/**
 * Acquire the key state of the mint.  Updates keys if necessary.
 * For every call to #TALER_MINT_key_state_acquire(), a matching call
 * to #TALER_MINT_key_state_release() must be made.
 *
 * @return the key state
 */
struct MintKeyState *
TALER_MINT_key_state_acquire (void)
{
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct MintKeyState *key_state;
  json_t *keys;

  GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
  if (internal_key_state->next_reload.abs_value_us <= now.abs_value_us)
  {
    TALER_MINT_key_state_release (internal_key_state);
    internal_key_state = NULL;
  }
  if (NULL == internal_key_state)
  {
    key_state = GNUNET_new (struct MintKeyState);
    key_state->denom_keys_array = json_array ();
    GNUNET_assert (NULL != key_state->denom_keys_array);
    key_state->sign_keys_array = json_array ();
    GNUNET_assert (NULL != key_state->sign_keys_array);
    key_state->denomkey_map = GNUNET_CONTAINER_multihashmap_create (32,
                                                                    GNUNET_NO);
    key_state->reload_time = GNUNET_TIME_absolute_get ();
    TALER_MINT_denomkeys_iterate (mintdir,
                                  &reload_keys_denom_iter,
                                  key_state);
    TALER_MINT_signkeys_iterate (mintdir,
                                 &reload_keys_sign_iter,
                                 key_state);
    key_state->next_reload = GNUNET_TIME_absolute_ntoh (key_state->current_sign_key_issue.issue.expire);
    if (0 == key_state->next_reload.abs_value_us)
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "No valid signing key found!\n");

    keys = json_pack ("{s:o, s:o, s:o, s:o}",
                      "master_pub",
                      TALER_JSON_from_data (&master_pub,
                                            sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)),
                      "signkeys", key_state->sign_keys_array,
                      "denoms", key_state->denom_keys_array,
                      "list_issue_date", TALER_JSON_from_abs (key_state->reload_time));
    key_state->keys_json = json_dumps (keys,
                                       JSON_INDENT(2));
    internal_key_state = key_state;
  }
  key_state = internal_key_state;
  key_state->refcnt++;
  GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));

  return key_state;
}


/**
 * Look up the issue for a denom public key.
 *
 * @param key state to look in
 * @param denom_pub denomination public key
 * @return the denomination key issue,
 *         or NULL if denom_pub could not be found
 */
struct TALER_MINT_DenomKeyIssuePriv *
TALER_MINT_get_denom_key (const struct MintKeyState *key_state,
                          const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub)
{
  struct GNUNET_HashCode hash;
  char *buf;
  size_t buf_len;

  buf_len = GNUNET_CRYPTO_rsa_public_key_encode (denom_pub,
                                                 &buf);
  GNUNET_CRYPTO_hash (buf,
                      buf_len,
                      &hash);
  GNUNET_free (buf);
  return GNUNET_CONTAINER_multihashmap_get (key_state->denomkey_map,
                                            &hash);
}


/**
 * Handle a signal, writing relevant signal numbers
 * (currently just SIGUSR1) to a pipe.
 *
 * @param signal_number the signal number
 */
static void
handle_signal (int signal_number)
{
  ssize_t res;
  char c = signal_number;

  if (SIGUSR1 == signal_number)
  {
    errno = 0;
    res = write (reload_pipe[1], &c, 1);
    if ((res < 0) && (EINTR != errno))
    {
      GNUNET_break (0);
      return;
    }
    if (0 == res)
    {
      GNUNET_break (0);
      return;
    }
  }
}


/**
 * Read signals from a pipe in a loop, and reload keys from disk if
 * SIGUSR1 is read from the pipe.
 *
 * @return #GNUNET_SYSERR on errors, otherwise does not return
 *          (FIXME: #3474)
 */
int
TALER_MINT_key_reload_loop (void)
{
  struct sigaction act;

  if (0 != pipe (reload_pipe))
  {
    fprintf (stderr,
             "Failed to create pipe.\n");
    return GNUNET_SYSERR;
  }
  memset (&act, 0, sizeof (struct sigaction));
  act.sa_handler = &handle_signal;

  if (0 != sigaction (SIGUSR1, &act, NULL))
  {
    fprintf (stderr,
             "Failed to set signal handler.\n");
    return GNUNET_SYSERR;
  }

  while (1)
  {
    char c;
    ssize_t res;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "(re-)loading keys\n");
    if (NULL != internal_key_state)
    {
      TALER_MINT_key_state_release (internal_key_state);
      internal_key_state = NULL;
    }
    /* This will re-initialize 'internal_key_state' with
       an initial refcnt of 1 */
    (void) TALER_MINT_key_state_acquire ();

read_again:
    errno = 0;
    res = read (reload_pipe[0], &c, 1);
    if ((res < 0) && (EINTR != errno))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    if (EINTR == errno)
      goto read_again;
  }
  return GNUNET_OK;
}


/**
 * Sign the message in @a purpose with the mint's signing key.
 *
 * @param purpose the message to sign
 * @param[OUT] sig signature over purpose using current signing key
 */
void
TALER_MINT_keys_sign (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                      struct GNUNET_CRYPTO_EddsaSignature *sig)

{
  struct MintKeyState *key_state;

  key_state = TALER_MINT_key_state_acquire ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&key_state->current_sign_key_issue.signkey_priv,
                                           purpose,
                                           sig));
  TALER_MINT_key_state_release (key_state);
}


/**
 * Function to call to handle the request by sending
 * back static data from the @a rh.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_keys (struct RequestHandler *rh,
                         struct MHD_Connection *connection,
                         void **connection_cls,
                         const char *upload_data,
                         size_t *upload_data_size)
{
  struct MintKeyState *key_state;
  struct MHD_Response *response;
  int ret;

  key_state = TALER_MINT_key_state_acquire ();
  response = MHD_create_response_from_buffer (strlen (key_state->keys_json),
                                              key_state->keys_json,
                                              MHD_RESPMEM_MUST_COPY);
  TALER_MINT_key_state_release (key_state);
  if (NULL == response)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  (void) MHD_add_response_header (response,
                                  "Content-Type",
                                  rh->mime_type);
  ret = MHD_queue_response (connection,
                            rh->response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
}



/* end of taler-mint-httpd_keystate.c */
