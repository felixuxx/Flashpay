/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_age_withdraw.c
 * @brief implements the age-withdraw command
 * @author Özgür Kesim
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_extensions.h"
#include "taler_testing_lib.h"

/**
 * State for a "age withdraw" CMD:
 */

struct AgeWithdrawState
{
  /*
   * Which reserve should we withdraw from?
   */
  const char *reserve_reference;

  /**
   * Expected HTTP response code to the request.
   */
  unsigned int expected_response_code;

  /**
   * The maximum age we commit to
   */
  uint8_t max_age;

  /**
   * Number of coins to withdraw
   */
  size_t num_coins;
};


struct TALER_TESTING_Command
TALER_TESTING_cmd_age_withdraw (const char *label,
                                const char *reserve_reference,
                                uint8_t max_age,
                                unsigned int expected_response_code,
                                const char *amount,
                                ...)
{
  struct AgeWithdrawState *aws;
  unsigned int cnt;
  va_list ap;

  aws = GNUNET_new (struct AgeWithdrawState);
  aws->max_age = max_age;
  aws->reserve_reference = reserve_reference;
  aws->expected_response_code = expected_response_code;

  cnt = 1;
  va_start (ap, amount);
  while (NULL != (va_arg (ap, const char *)))
    cnt++;
  aws->num_coins = cnt;
  aws->coins = GNUNET_new_array (cnt,
                                 struct CoinState);
  va_end (ap);
  va_start (ap, amount);
  for (unsigned int i = 0; i<ws->num_coins; i++)
  {
    struct CoinState *cs = &ws->coins[i];

    if (0 < age)
    {
      struct TALER_AgeCommitmentProof *acp;
      struct TALER_AgeCommitmentHash *hac;
      struct GNUNET_HashCode seed;
      struct TALER_AgeMask mask;

      acp = GNUNET_new (struct TALER_AgeCommitmentProof);
      hac = GNUNET_new (struct TALER_AgeCommitmentHash);
      mask = TALER_extensions_get_age_restriction_mask ();
      GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                  &seed,
                                  sizeof(seed));

      if (GNUNET_OK !=
          TALER_age_restriction_commit (
            &mask,
            age,
            &seed,
            acp))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failed to generate age commitment for age %d at %s\n",
                    age,
                    label);
        GNUNET_assert (0);
      }

      TALER_age_commitment_hash (&acp->commitment,
                                 hac);
      cs->age_commitment_proof = acp;
      cs->h_age_commitment = hac;
    }

    if (GNUNET_OK !=
        TALER_string_to_amount (amount,
                                &cs->amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse amount `%s' at %s\n",
                  amount,
                  label);
      GNUNET_assert (0);
    }
    /* move on to next vararg! */
    amount = va_arg (ap, const char *);
  }
  GNUNET_assert (NULL == amount);
  va_end (ap);

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &age_withdraw_run,
      .cleanup = &age_withdraw_cleanup,
      .traits = &age_withdraw_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_age_withdraw.c */
