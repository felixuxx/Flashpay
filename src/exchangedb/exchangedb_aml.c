/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

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
 * @file exchangedb_aml.c
 * @brief helper function to handle AML programs
 * @author Christian Grothoff
 */
#include "taler_exchangedb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_common.h>


enum GNUNET_DB_QueryStatus
TALER_EXCHANGEDB_persist_aml_program_result (
  struct TALER_EXCHANGEDB_Plugin *plugin,
  uint64_t process_row,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const json_t *attributes,
  const struct TALER_AttributeEncryptionKeyP *attribute_key,
  unsigned int birthday,
  struct GNUNET_TIME_Absolute expiration,
  const struct TALER_NormalizedPaytoHashP *account_id,
  const struct TALER_KYCLOGIC_AmlProgramResult *apr)
{
  enum GNUNET_DB_QueryStatus qs;
  size_t eas = 0;
  void *ea = NULL;

  /* TODO: also clear lock on AML program (#9303) */
  switch (apr->status)
  {
  case TALER_KYCLOGIC_AMLR_FAILURE:
    qs = plugin->insert_kyc_failure (
      plugin->cls,
      process_row,
      account_id,
      provider_name,
      provider_user_id,
      provider_legitimization_id,
      apr->details.failure.error_message,
      apr->details.failure.ec);
    GNUNET_break (qs > 0);
    return qs;
  case TALER_KYCLOGIC_AMLR_SUCCESS:
    if (NULL != attributes)
    {
      TALER_CRYPTO_kyc_attributes_encrypt (attribute_key,
                                           attributes,
                                           &ea,
                                           &eas);
    }
    qs = plugin->insert_kyc_measure_result (
      plugin->cls,
    process_row,
    account_id,
    birthday,
    GNUNET_TIME_timestamp_get (),
    provider_name,
    provider_user_id,
    provider_legitimization_id,
    expiration,
    apr->details.success.account_properties,
    apr->details.success.new_rules,
    apr->details.success.to_investigate,
    apr->details.success.num_events,
    apr->details.success.events,
    eas,
    ea);
    GNUNET_free (ea);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Stored encrypted KYC process #%llu attributes: %d\n",
                (unsigned long long) process_row,
                qs);
    GNUNET_break (qs > 0);
    return qs;
  }
  GNUNET_assert (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}
