/**
 * @file include/types.h
 * @brief This files defines the various data and message types in TALER.
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 */

#ifndef TYPES_H_
#define TYPES_H_

#include "taler_rsa.h"


/**
 * Public information about a coin.
 */
struct TALER_CoinPublicInfo
{
  /**
   * The coin's public key.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;

  /*
   * The public key signifying the coin's denomination.
   */
  struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;

  /**
   * Signature over coin_pub by denom_pub.
   */
  struct TALER_RSA_Signature denom_sig;
};


/**
 * Request to withdraw coins from a reserve.
 */
struct TALER_WithdrawRequest
{
  /**
   * Signature over the rest of the message
   * by the withdraw public key.
   */
  struct GNUNET_CRYPTO_EddsaSignature sig;

  /**
   * Purpose must be TALER_SIGNATURE_WITHDRAW.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Reserve public key.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;

  /**
   * Denomination public key for the coin that is withdrawn.
   */
  struct TALER_RSA_PublicKeyBinaryEncoded denomination_pub;

  /**
   * Purpose containing coin's blinded public key.
   */
  struct TALER_RSA_BlindedSignaturePurpose coin_envelope;
};



/**
 * Data type for messages
 */
struct TALER_MessageHeader
{
  /**
   * The type of the message in Network-byte order (NBO)
   */
  uint16_t type;

  /**
   * The size of the message in NBO
   */
  uint16_t size;
};

/*****************/
/* Message types */
/*****************/

/**
 * The message type of a blind signature
 */
#define TALER_MSG_TYPE_BLINDED_SIGNATURE  1

/**
 * The message type of a blinded message
 */
#define TALER_MSG_TYPE_BLINDED_MESSAGE 2

/**
 * The message type of an unblinded signature
 * @FIXME: Not currently used
 */
#define TALER_MSG_TYPE_UNBLINDED_SIGNATURE 3

/**
 * The type of a blinding residue message
 * @FIXME: Not currently used
 */
#define TALER_MSG_TYPE_BLINDING_RESIDUE 4

/**
 * The type of a message containing the blinding factor
 */
#define TALER_MSG_TYPE_BLINDING_FACTOR 5


#endif  /* TYPES_H_ */

/* end of include/types.h */
