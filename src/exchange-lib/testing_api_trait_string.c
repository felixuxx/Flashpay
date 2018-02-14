/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
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
 * @file exchange-lib/testing_api_trait_string.c
 * @brief offers strings traits.  Mostly used to offer
 *        stringified JSONs.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_WIRE_DETAILS "wire-details"
#define TALER_TESTING_TRAIT_CONTRACT_TERMS "contract-terms"
#define TALER_TESTING_TRAIT_TRANSFER_SUBJECT "transfer-subject"
#define TALER_TESTING_TRAIT_AMOUNT "amount"
#define TALER_TESTING_TRAIT_URL "url"

/**
 * Obtain contract terms from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param contract_terms[out] where to write the contract
 *        terms.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_contract_terms
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **contract_terms)
{
  return cmd->traits (cmd->cls,
                      (void **) contract_terms,
                      TALER_TESTING_TRAIT_CONTRACT_TERMS,
                      index);
}

/**
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param contract_terms contract terms to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_contract_terms
  (unsigned int index,
   const char *contract_terms)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_CONTRACT_TERMS,
    .ptr = (const void *) contract_terms
  };
  return ret;
}


/**
 * Obtain wire details from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param wire_details[out] where to write the wire details.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_wire_details
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **wire_details)
{
  return cmd->traits (cmd->cls,
                      (void **) wire_details,
                      TALER_TESTING_TRAIT_WIRE_DETAILS,
                      index);
}

/**
 * Offer wire details in a trait.
 *
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param wire_details wire details to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wire_details
  (unsigned int index,
   const char *wire_details)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_WIRE_DETAILS,
    .ptr = (const void *) wire_details
  };
  return ret;
}


/**
 * Obtain a transfer subject from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index always (?) zero, as one command sticks
 *        to one bank transfer
 * @param transfer_subject[out] where to write the wire details.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_transfer_subject
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   char **transfer_subject)
{
  return cmd->traits (cmd->cls,
                      (void **) transfer_subject,
                      TALER_TESTING_TRAIT_TRANSFER_SUBJECT,
                      index);
}

/**
 * Offer wire details in a trait.
 *
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param wire_details wire details to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_transfer_subject
  (unsigned int index,
   char *transfer_subject)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_TRANSFER_SUBJECT,
    .ptr = (const void *) transfer_subject
  };
  return ret;
}


/**
 * Obtain an amount from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which amount is to be picked, in case
 *        multiple are offered.
 * @param amount[out] where to write the wire details.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_amount
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **amount)
{
  return cmd->traits (cmd->cls,
                      (void **) amount,
                      TALER_TESTING_TRAIT_AMOUNT,
                      index);
}

/**
 * Offer amount in a trait.
 *
 * @param index which amount is to be picked, in case
 *        multiple are offered.
 * @param amount the amount to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_amount
  (unsigned int index,
   const char *amount)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_AMOUNT,
    .ptr = (const void *) amount
  };
  return ret;
}


/**
 * Obtain a url from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which url is to be picked, in case
 *        multiple are offered.
 * @param amount[out] where to write the url.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_url
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **url)
{
  return cmd->traits (cmd->cls,
                      (void **) url,
                      TALER_TESTING_TRAIT_URL,
                      index);
}

/**
 * Offer url in a trait.
 *
 * @param index which url is to be picked, in case
 *        multiple are offered.
 * @param url the url to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_url
  (unsigned int index,
   const char *url)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_URL,
    .ptr = (const void *) url
  };
  return ret;
}




/* end of testing_api_trait_string.c */
