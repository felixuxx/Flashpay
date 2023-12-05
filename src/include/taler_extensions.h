/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file include/taler_extensions.h
 * @brief Interface for extensions
 * @author Özgür Kesim
 */
#ifndef TALER_EXTENSIONS_H
#define TALER_EXTENSIONS_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_extensions_policy.h"


#define TALER_EXTENSION_SECTION_PREFIX "exchange-extension-"

enum TALER_Extension_Type
{
  TALER_Extension_PolicyNull                 = 0,

  TALER_Extension_AgeRestriction             = 1,
  TALER_Extension_PolicyMerchantRefund       = 2,
  TALER_Extension_PolicyBrandtVickeryAuction = 3,
  TALER_Extension_PolicyEscrowedPayment      = 4,

  TALER_Extension_MaxPredefined              = 5 // Must be last of the predefined
};


/* Forward declarations */
enum TALER_PolicyFulfillmentState;
struct TALER_PolicyFulfillmentOutcome;

/*
 * @brief Represents the implementation of an extension.
 *
 * An "Extension" is an optional feature for the Exchange.
 * There are only two types of extensions:
 *
 * a) Age restriction:  This is a special feature that directly interacts with
 * denominations and coins, but is not define policies during deposits, see b).
 * The implementation of this extension doesn't have to implement any of the
 * http- or depost-handlers in the struct.
 *
 * b) Policies for deposits:  These are extensions that define policies (such
 * as refund, escrow or auctions) for deposit requests.  These extensions have
 * to implement at least the deposit- and post-http-handler in the struct to be
 * functional.
 *
 * In addition to the handlers defined in this struct, an extension must also
 * be a plugin in the GNUNET_Plugin sense.  That is, it must implement the
 * functions
 *    1: (void *ext)libtaler_extension_<name>_init(void *cfg)
 * and
 *    2: (void *)libtaler_extension_<name>_done(void *)
 *
 * In 1:, the input will be the GNUNET_CONFIGURATION_Handle to the TALER
 * configuration and the output must be the struct TALER_Extension * on
 * success, NULL otherwise.
 *
 * In 2:, no arguments are passed and NULL is expected to be returned.
 */
struct TALER_Extension
{
  /**
   * Type of the extension.  Only one extension of a type can be loaded
   * at any time.
   */
  enum TALER_Extension_Type type;

  /**
   * The name of the extension, must be unique among all loaded extensions.  It
   * is used in URLs for /extension/$NAME as well.
   */
  char *name;

  /**
   * Criticality of the extension.  It has the same semantics as "critical" has
   * for extensions in X.509:
   * - if "true", the client must "understand" the extension before proceeding,
   * - if "false", clients can safely skip extensions they do not understand.
   * (see https://datatracker.ietf.org/doc/html/rfc5280#section-4.2)
   */
  bool critical;

  /**
   * Version of the extension must be provided in Taler's protocol version ranges notation, see
   * https://docs.taler.net/core/api-common.html#protocol-version-ranges
   */
  char *version;

  /**
   * If the extension is marked as enabled, it will be listed in the
   * "extensions" field in the "/keys" response.
   */
  bool enabled;

  /**
   * Opaque (public) configuration object, set by the extension.
   */
  void *config;


  /**
   * @brief Handler to to disable the extension.
   *
   * @param ext The current extension object
   */
  void (*disable)(struct TALER_Extension *ext);

  /**
   * @brief Handler to read an extension-specific configuration in JSON
   * encoding and enable the extension.  Must be implemented by the extension.
   *
   * @param[in] ext The extension object. If NULL, the configuration will only be checked.
   * @param[in,out] config A JSON blob
   * @return GNUNET_OK if the json was a valid configuration for the extension.
   */
  enum GNUNET_GenericReturnValue (*load_config)(
    const json_t *config,
    struct TALER_Extension *ext);

  /**
   * @brief Handler to return the manifest of the extension in JSON encoding.
   *
   * See
   * https://docs.taler.net/design-documents/006-extensions.html#tsref-type-Extension
   * for the definition.
   *
   * @param ext The extension object
   * @return The JSON encoding of the extension, if enabled, NULL otherwise.
   */
  json_t *(*manifest)(
    const struct TALER_Extension *ext);

  /* =========================
   *  Policy related handlers
   * =========================
   */

  /**
   * @brief Handler to check an incoming policy and create a
   * TALER_PolicyDetails. Can be NULL;
   *
   * When a deposit request refers to this extension in its policy
   * (see https://docs.taler.net/core/api-exchange.html#deposit), this handler
   * will be called before the deposit transaction.
   *
   * @param[in]  currency Currency used in the exchange
   * @param[in]  policy_json Details about the policy, provided by the client
   *             during a deposit request.
   * @param[out] details On success, will contain the details to the policy,
   *             evaluated by the corresponding policy handler.
   * @param[out] error_hint On error, will contain a hint
   * @return     GNUNET_OK if the data was accepted by the extension.
   */
  enum GNUNET_GenericReturnValue (*create_policy_details)(
    const char *currency,
    const json_t *policy_json,
    struct TALER_PolicyDetails *details,
    const char **error_hint);

  /**
   * @brief Handler for POST-requests to the /extensions/$name endpoint. Can be NULL.
   *
   * @param[in] root The JSON body from the request
   * @param[in] args Additional query parameters of the request.
   * @param[in,out] details List of policy details related to the incoming fulfillment proof
   * @param[in] details_len Size of the list @e details
   * @param[out] output JSON output to return to the client
   * @return GNUNET_OK on success.
   */
  enum GNUNET_GenericReturnValue (*policy_post_handler)(
    const json_t *root,
    const char *const args[],
    struct TALER_PolicyDetails *details,
    size_t details_len,
    json_t **output);

  /**
   * @brief Handler for GET-requests to the /extensions/$name endpoint.  Can be NULL.
   *
   * @param connection The current connection
   * @param root The JSON body from the request
   * @param args Additional query parameters of the request.
   * @return MDH result
   */
  MHD_RESULT (*policy_get_handler)(
    struct MHD_Connection *connection,
    const char *const args[]);
};


/*
 * @brief simply linked list of extensions
 */

struct TALER_Extensions
{
  struct TALER_Extensions *next;
  const struct TALER_Extension *extension;
};

/**
 * Generic functions for extensions
 */

/**
 * @brief Loads the extensions as shared libraries, as specified in the given
 * TALER configuration.
 *
 * @param cfg Handle to the TALER configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if unknown extensions were found
 *         or any particular configuration couldn't be parsed.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_init (
  const struct GNUNET_CONFIGURATION_Handle *cfg);

/*
 * @brief Parses a given JSON object as an extension manifest.
 *
 * @param[in] obj JSON object to parse as an extension manifest
 * @param{out] critical will be set to 1 if the extension is critical according to obj
 * @param[out] version will be set to the version of the extension according to obj
 * @param[out] config will be set to the configuration of the extension according to obj
 * @return OK on success, Error otherwise
 */
enum GNUNET_GenericReturnValue
TALER_extensions_parse_manifest (
  json_t *obj,
  int *critical,
  const char **version,
  json_t **config);

/*
 * @brief Loads extensions according to the manifests.
 *
 * The JSON object must be of type ExtensionsManifestsResponse as described
 * in https://docs.taler.net/design-documents/006-extensions.html#exchange
 *
 * @param cfg JSON object containing the manifests for all extensions
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if unknown extensions were
 *  found or any particular configuration couldn't be parsed.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_load_manifests (
  const json_t *manifests);

/*
 * @brief Returns the head of the linked list of extensions.
 */
const struct TALER_Extensions *
TALER_extensions_get_head (void);

/**
 * @brief Finds and returns a supported extension by a given type.
 *
 * @param type of the extension to lookup
 * @return extension found, or NULL (should not happen!)
 */
const struct TALER_Extension *
TALER_extensions_get_by_type (
  enum TALER_Extension_Type type);


/**
 * @brief Finds and returns a supported extension by a given name.
 *
 * @param name name of the extension to lookup
 * @return the extension, if found, NULL otherwise
 */
const struct TALER_Extension *
TALER_extensions_get_by_name (
  const char *name);

/**
 * @brief Check if a given type of an extension is enabled
 *
 * @param type type of to check
 * @return true enabled, false if not enabled, will assert if type is not found.
 */
bool
TALER_extensions_is_enabled_type (
  enum TALER_Extension_Type type);

/**
 * @brief Check if an extension is enabled
 *
 * @param extension The extension handler.
 * @return true enabled, false if not enabled, will assert if type is not found.
 */
bool
TALER_extensions_is_enabled (
  const struct TALER_Extension *extension);

/*
 * Verify the signature of a given JSON object for extensions with the master
 * key of the exchange.
 *
 * The JSON object must be of type ExtensionsManifestsResponse as described in
 * https://docs.taler.net/design-documents/006-extensions.html#exchange
 *
 * @param extensions JSON object with the extension configuration
 * @param extensions_sig signature of the hash of the JSON object
 * @param master_pub public key to verify the signature
 * @return GNUNET_OK on success, GNUNET_SYSERR when hashing of the JSON fails
 * and GNUNET_NO if the signature couldn't be verified.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_verify_manifests_signature (
  const json_t *manifests,
  struct TALER_MasterSignatureP *extensions_sig,
  struct TALER_MasterPublicKeyP *master_pub);


/*
 * TALER Age Restriction Extension
 *
 * This extension is special insofar as it directly interacts with coins and
 * denominations.
 *
 * At the same time, it doesn't implement and http- or deposit-handlers.
 */

#define TALER_EXTENSION_SECTION_AGE_RESTRICTION (TALER_EXTENSION_SECTION_PREFIX  \
                                                 "age_restriction")

/**
 * The default age mask represents the age groups
 * 0-7, 8-9, 10-11, 12-13, 14-15, 16-17, 18-20, 21-...
 */
#define TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_GROUPS "8:10:12:14:16:18:21"


/*
 * @brief Configuration for Age Restriction
 */
struct TALER_AgeRestrictionConfig
{
  struct TALER_AgeMask mask;
  uint8_t num_groups;
};


/**
 * @brief Retrieve the age restriction configuration
 *
 * @return age restriction configuration if present, otherwise NULL.
 */
const struct TALER_AgeRestrictionConfig *
TALER_extensions_get_age_restriction_config (void);

/**
 * @brief Check if age restriction is enabled
 *
 * @return true, if age restriction is loaded, configured and enabled; otherwise false.
 */
bool
TALER_extensions_is_age_restriction_enabled (void);

/**
 * @brief Return the age mask for age restriction
 *
 * @return configured age mask, if age restriction is loaded, configured and enabled; otherwise zero mask.
 */
struct TALER_AgeMask
TALER_extensions_get_age_restriction_mask (void);

#endif
