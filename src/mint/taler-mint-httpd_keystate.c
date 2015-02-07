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
 * Mint key state.  Never use directly, instead access via
 * #TALER_MINT_key_state_acquire and #TALER_MINT_key_state_release.
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
  char *buf;
  size_t buf_len;
  json_t *dk_json = json_object ();

  json_object_set_new (dk_json,
                       "master_sig",
                       TALER_JSON_from_data (&dki->signature,
                                             sizeof (struct GNUNET_CRYPTO_EddsaSignature)));
  json_object_set_new (dk_json,
                       "stamp_start",
                       TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (dki->start)));
  json_object_set_new (dk_json,
                       "stamp_expire_withdraw",
                       TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (dki->expire_withdraw)));
  json_object_set_new (dk_json,
                       "stamp_expire_deposit",
                       TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (dki->expire_spend)));

  buf_len = GNUNET_CRYPTO_rsa_public_key_encode (dki->denom_pub,
                                                 &buf);
  json_object_set_new (dk_json,
                       "denom_pub",
                       TALER_JSON_from_data (buf,
                                             buf_len));
  GNUNET_free (buf);
  json_object_set_new (dk_json,
                       "value",
                       TALER_JSON_from_amount (TALER_amount_ntoh (dki->value)));
  json_object_set_new (dk_json,
                       "fee_withdraw",
                       TALER_JSON_from_amount (TALER_amount_ntoh (dki->fee_withdraw)));
  json_object_set_new (dk_json,
                       "fee_deposit",
                       TALER_JSON_from_amount (TALER_amount_ntoh (dki->fee_deposit)));
  json_object_set_new (dk_json,
                       "fee_refresh",
                       TALER_JSON_from_amount (TALER_amount_ntoh (dki->fee_refresh)));
  return dk_json;
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
  json_t *sk_json = json_object ();

  json_object_set_new (sk_json,
                       "stamp_start",
                       TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (ski->start)));
  json_object_set_new (sk_json,
                       "stamp_expire",
                       TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (ski->expire)));
  json_object_set_new (sk_json,
                       "master_sig",
                       TALER_JSON_from_data (&ski->signature,
                                             sizeof (struct GNUNET_CRYPTO_EddsaSignature)));
  json_object_set_new (sk_json,
                       "key",
                       TALER_JSON_from_data (&ski->signkey_pub,
                                             sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)));
  return sk_json;
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
    GNUNET_abort ();
  }
  return rel;
}


/**
 * Iterator for denomination keys.
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
  struct GNUNET_TIME_Absolute stamp_provide;
  struct GNUNET_HashCode denom_key_hash;
  int res;

  stamp_provide = GNUNET_TIME_absolute_add (ctx->reload_time,
                                            TALER_MINT_conf_duration_provide ());

  if (GNUNET_TIME_absolute_ntoh (dki->issue.expire_spend).abs_value_us < ctx->reload_time.abs_value_us)
  {
    // this key is expired
    return GNUNET_OK;
  }
  if (GNUNET_TIME_absolute_ntoh (dki->issue.start).abs_value_us > stamp_provide.abs_value_us)
  {
    // we are to early for this key
    return GNUNET_OK;
  }

  GNUNET_CRYPTO_hash (&dki->issue.denom_pub,
                      sizeof (struct GNUNET_CRYPTO_EddsaPublicKey),
                      &denom_key_hash);

  res = GNUNET_CONTAINER_multihashmap_put (ctx->denomkey_map,
                                           &denom_key_hash,
                                           GNUNET_memdup (dki, sizeof (struct TALER_MINT_DenomKeyIssuePriv)),
                                           GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY);
  if (GNUNET_OK != res)
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Duplicate denomination key\n");

  json_array_append_new (ctx->denom_keys_array,
                         denom_key_issue_to_json (&dki->issue));

  return GNUNET_OK;
}


/**
 * Iterator for sign keys.
 *
 * @param cls closure
 * @param ski the sign key issue
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_keys_sign_iter (void *cls,
                       const struct TALER_MINT_SignKeyIssuePriv *ski)
{
  struct MintKeyState *ctx = cls;
  struct GNUNET_TIME_Absolute stamp_provide;

  stamp_provide = GNUNET_TIME_absolute_add (ctx->reload_time,
                                            TALER_MINT_conf_duration_provide (cfg));

  if (GNUNET_TIME_absolute_ntoh (ski->issue.expire).abs_value_us < ctx->reload_time.abs_value_us)
  {
    // this key is expired
    return GNUNET_OK;
  }

  if (GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us > stamp_provide.abs_value_us)
  {
    // we are to early for this key
    return GNUNET_OK;
  }

  // the signkey is valid for now, check
  // if it's more recent than the current one!
  if (GNUNET_TIME_absolute_ntoh (ctx->current_sign_key_issue.issue.start).abs_value_us >
      GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us)
    ctx->current_sign_key_issue = *ski;


  ctx->next_reload = GNUNET_TIME_absolute_min (ctx->next_reload,
                                               GNUNET_TIME_absolute_ntoh (ski->issue.expire));

  json_array_append_new (ctx->sign_keys_array,
                         sign_key_issue_to_json (&ski->issue));

  return GNUNET_OK;
}


/**
 * Load the mint's key state from disk.
 *
 * @return fresh key state (with reference count 1)
 */
static struct MintKeyState *
reload_keys ()
{
  struct MintKeyState *key_state;
  json_t *keys;

  key_state = GNUNET_new (struct MintKeyState);
  key_state->refcnt = 1;

  key_state->next_reload = GNUNET_TIME_UNIT_FOREVER_ABS;

  key_state->denom_keys_array = json_array ();
  GNUNET_assert (NULL != key_state->denom_keys_array);

  key_state->sign_keys_array = json_array ();
  GNUNET_assert (NULL != key_state->sign_keys_array);

  key_state->denomkey_map = GNUNET_CONTAINER_multihashmap_create (32,
                                                                  GNUNET_NO);
  GNUNET_assert (NULL != key_state->denomkey_map);

  key_state->reload_time = GNUNET_TIME_absolute_get ();

  TALER_MINT_denomkeys_iterate (mintdir, &reload_keys_denom_iter, key_state);
  TALER_MINT_signkeys_iterate (mintdir, &reload_keys_sign_iter, key_state);

  keys = json_pack ("{s:o, s:o, s:o, s:o}",
                    "master_pub", TALER_JSON_from_data (&master_pub,
                                                        sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)),
                    "signkeys", key_state->sign_keys_array,
                    "denoms", key_state->denom_keys_array,
                    "list_issue_date", TALER_JSON_from_abs (key_state->reload_time));

  key_state->keys_json = json_dumps (keys, JSON_INDENT(2));

  return key_state;
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
    GNUNET_free (key_state);
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
}


/**
 * Acquire the key state of the mint.  Updates keys if necessary.
 * For every call to #TALER_MINT_key_state_acquire, a matching call
 * to #TALER_MINT_key_state_release must be made.
 *
 * @return the key state
 */
struct MintKeyState *
TALER_MINT_key_state_acquire (void)
{
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct MintKeyState *key_state;

  GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
  if (NULL == internal_key_state)
  {
    internal_key_state = reload_keys ();
  }
  else if (internal_key_state->next_reload.abs_value_us <= now.abs_value_us)
  {
    GNUNET_assert (0 < internal_key_state->refcnt);
    internal_key_state->refcnt--;
    if (0 == internal_key_state->refcnt)
      GNUNET_free (internal_key_state);
    internal_key_state = reload_keys ();
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
    GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
    if (NULL != internal_key_state)
    {
      GNUNET_assert (0 != internal_key_state->refcnt);
      internal_key_state->refcnt -= 1;
      if (0 == internal_key_state->refcnt)
        GNUNET_free (internal_key_state);
    }
    internal_key_state = reload_keys ();
    GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
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
 * Sign the message in @a purpose with the mint's signing
 * key.
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


/* end of taler-mint-httpd_keystate.c */
