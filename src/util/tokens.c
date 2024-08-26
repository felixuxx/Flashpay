/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file tokens.c
 * @brief token family utility functions
 * @author Christian Blättler
 */
#include "platform.h"
#include "taler_util.h"


void
TALER_token_issue_sig_free (struct TALER_TokenIssueSignatureP *issue_sig)
{
  if (NULL != issue_sig->signature)
  {
    GNUNET_CRYPTO_unblinded_sig_decref (issue_sig->signature);
    issue_sig->signature = NULL;
  }
}


void
TALER_blinded_issue_sig_free (
  struct TALER_TokenIssueBlindSignatureP *issue_sig)
{
  if (NULL != issue_sig->signature)
  {
    GNUNET_CRYPTO_blinded_sig_decref (issue_sig->signature);
    issue_sig->signature = NULL;
  }
}


void
TALER_token_use_setup_random (struct TALER_TokenUseMasterSecretP *master)
{
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              master,
                              sizeof (*master));
}


void
TALER_token_use_setup_priv (
  const struct TALER_TokenUseMasterSecretP *master,
  const struct TALER_TokenUseMerchantValues *alg_values,
  struct TALER_TokenUsePrivateKeyP *token_priv)
{
  /* TODO: Maybe extract common code between this
           function and TALER_planchet_setup_coin_priv (). */
  const struct GNUNET_CRYPTO_BlindingInputValues *bi
    = alg_values->blinding_inputs;

  switch (bi->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    GNUNET_break (0);
    memset (token_priv,
            0,
            sizeof (*token_priv));
    return;
  case GNUNET_CRYPTO_BSA_RSA:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (token_priv,
                                      sizeof (*token_priv),
                                      "token",
                                      strlen ("token"),
                                      master,
                                      sizeof(*master),
                                      NULL,
                                      0));
    return;
  case GNUNET_CRYPTO_BSA_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (token_priv,
                                      sizeof (*token_priv),
                                      "token",
                                      strlen ("token"),
                                      master,
                                      sizeof(*master),
                                      &bi->details.cs_values,
                                      sizeof(bi->details.cs_values),
                                      NULL,
                                      0));
    return;
  }
  GNUNET_assert (0);
}


void
TALER_token_use_blinding_secret_create (
  const struct TALER_TokenUseMasterSecretP *master,
  const struct TALER_TokenUseMerchantValues *alg_values,
  union GNUNET_CRYPTO_BlindingSecretP *bks)
{
  /* TODO: Extract common code between this
           function and TALER_planchet_blinding_secret_create (). */
  const struct GNUNET_CRYPTO_BlindingInputValues *bi =
    alg_values->blinding_inputs;

  switch (bi->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    GNUNET_break (0);
    return;
  case GNUNET_CRYPTO_BSA_RSA:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (&bks->rsa_bks,
                                      sizeof (bks->rsa_bks),
                                      "bks",
                                      strlen ("bks"),
                                      master,
                                      sizeof(*master),
                                      NULL,
                                      0));
    return;
  case GNUNET_CRYPTO_BSA_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (&bks->nonce,
                                      sizeof (bks->nonce),
                                      "bseed",
                                      strlen ("bseed"),
                                      master,
                                      sizeof(*master),
                                      &bi->details.cs_values,
                                      sizeof(bi->details.cs_values),
                                      NULL,
                                      0));
    return;
  }
  GNUNET_assert (0);
}


const struct TALER_TokenUseMerchantValues *
TALER_token_blind_input_rsa_singleton ()
{
  static struct GNUNET_CRYPTO_BlindingInputValues bi = {
    .cipher = GNUNET_CRYPTO_BSA_RSA
  };
  static struct TALER_TokenUseMerchantValues alg_values = {
    .blinding_inputs = &bi
  };
  return &alg_values;
}


void
TALER_token_blind_input_copy (struct TALER_TokenUseMerchantValues *bi_dst,
                              const struct TALER_TokenUseMerchantValues *bi_src)
{
  if (bi_src == TALER_token_blind_input_rsa_singleton ())
  {
    *bi_dst = *bi_src;
    return;
  }
  bi_dst->blinding_inputs
    = GNUNET_CRYPTO_blinding_input_values_incref (bi_src->blinding_inputs);
}


enum GNUNET_GenericReturnValue
TALER_token_issue_sign (const struct TALER_TokenIssuePrivateKeyP *issue_priv,
                        const struct TALER_TokenEnvelope *envelope,
                        struct TALER_TokenIssueBlindSignatureP *issue_sig)
{
  issue_sig->signature
    = GNUNET_CRYPTO_blind_sign (issue_priv->private_key,
                                "tk", /* TODO: What is a good value here? */
                                envelope->blinded_pub);
  if (NULL == issue_sig->signature)
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_token_issue_verify (const struct TALER_TokenUsePublicKeyP *use_pub,
                          const struct TALER_TokenIssuePublicKeyP *issue_pub,
                          const struct TALER_TokenIssueSignatureP *ub_sig)
{
  struct GNUNET_HashCode h_use_pub;

  GNUNET_CRYPTO_hash (&use_pub->public_key,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &h_use_pub);

  if (GNUNET_OK !=
      GNUNET_CRYPTO_blind_sig_verify (issue_pub->public_key,
                                      ub_sig->signature,
                                      &h_use_pub,
                                      sizeof (h_use_pub)))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_token_issue_sig_unblind (
  struct TALER_TokenIssueSignatureP *issue_sig,
  const struct TALER_TokenIssueBlindSignatureP *blinded_sig,
  const union GNUNET_CRYPTO_BlindingSecretP *secret,
  const struct TALER_TokenUsePublicKeyHashP *use_pub_hash,
  const struct TALER_TokenUseMerchantValues *alg_values,
  const struct TALER_TokenIssuePublicKeyP *issue_pub)
{
  issue_sig->signature
    = GNUNET_CRYPTO_blind_sig_unblind (blinded_sig->signature,
                                       secret,
                                       &use_pub_hash->hash,
                                       sizeof (use_pub_hash->hash),
                                       alg_values->blinding_inputs,
                                       issue_pub->public_key);
  if (NULL == issue_sig->signature)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}
