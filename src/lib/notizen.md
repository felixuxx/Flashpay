# Notes re: planchets and blinding

## `TALER_denom_blind()`

```
Blind coin for blind signing with @a dk using blinding secret @a coin_bks.
```

- `@param[out] c_hash resulting hashed coin`
- `@param[out] blinded_planchet planchet data to initialize`

## `TALER_planchet_prepare()`

Prepare a planchet for withdrawal.  Creates and blinds a coin.

- calls `TALER_denom_blind()!`
- `@param[out] c_hash set to the hash of the public key of the coin (needed later)`
- `@param[out] pd set to the planchet detail for TALER_MERCHANT_tip_pickup() and other withdraw operations, pd->blinded_planchet.cipher will be set to cipher from @a dk`


## `TALER_coin_ev_hash`

Compute the hash of a blinded coin.

- `@param blinded_planchet blinded planchet`
- `@param denom_hash hash of the denomination publick key`
- `@param[out] bch where to write the hash, type struct TALER_BlindedCoinHashP`

**Where is this called!?**

```
taler-exchange-httpd_refreshes_reveal.c
605:    TALER_coin_ev_hash (&rrc->blinded_planchet,

taler-exchange-httpd_recoup.c
290:        TALER_coin_ev_hash (&blinded_planchet,

taler-exchange-httpd_withdraw.c
581:      TALER_coin_ev_hash (&wc.blinded_planchet,

taler-exchange-httpd_age-withdraw_reveal.c
350:    ret = TALER_coin_ev_hash (&detail.blinded_planchet,

taler-exchange-httpd_recoup-refresh.c
284:    TALER_coin_ev_hash (&blinded_planchet,

taler-exchange-httpd_age-withdraw.c
279:      ret = TALER_coin_ev_hash (&awc->coin_evs[c],
884:    TALER_coin_ev_hash (&awc->coin_evs[i],

taler-exchange-httpd_batch-withdraw.c
832:        TALER_coin_ev_hash (&pc->blinded_planchet,
```


## `TALER_coin_pub_hash`

Compute the hash of a coin.

- `@param coin_pub public key of the coin`
- `@param age_commitment_hash hash of the age commitment vector. NULL, if no age commitment was set`
- `@param[out] coin_h where to write the hash`

**Where is this called!?**

### In `lib/crypto.c`, function `TALER_test_coin_valid`.

```
Check if a coin is valid; that is, whether the denomination key
exists, is not expired, and the signature is correct.

@param coin_public_info the coin public info to check for validity
@param denom_pub denomination key, must match @a coin_public_info's `denom_pub_hash`
@return #GNUNET_YES if the coin is valid,
        #GNUNET_NO if it is invalid
        #GNUNET_SYSERR if an internal error occurred
```

It then calls `TALER_denom_pub_verify` on the result of `TALER_coin_pub_hash` and the signature


### In `util/denom.c`, function `TALER_denom_blind`

## `TALER_EXCHANGE_batch_withdraw` vs `TALER_EXCHANGE_batch_withdraw2`

### `TALER_EXCHANGE_batch_withdraw`

```
/**
 * Withdraw multiple coins from the exchange using a /reserves/$RESERVE_PUB/batch-withdraw
 * request.  This API is typically used by a wallet to withdraw many coins from a
 * reserve.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param curl_ctx The curl context to use
 * @param exchange_url The base-URL of the exchange
 * @param keys The /keys material from the exchange
 * @param reserve_priv private key of the reserve to withdraw from
 * @param wci_length number of entries in @a wcis
 * @param wcis inputs that determine the planchets
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_BatchWithdrawHandle *
TALER_EXCHANGE_batch_withdraw (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int wci_length,
  const struct TALER_EXCHANGE_WithdrawCoinInput wcis[static wci_length],
  TALER_EXCHANGE_BatchWithdrawCallback res_cb,
  void *res_cb_cls);
```

### `TALER_EXCHANGE_batch_withdraw2`

```
/**
 * Withdraw a coin from the exchange using a /reserves/$RESERVE_PUB/batch-withdraw
 * request.  This API is typically used by a merchant to withdraw a tip
 * where the blinding factor is unknown to the merchant.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param curl_ctx The curl context to use
 * @param exchange_url The base-URL of the exchange
 * @param keys The /keys material from the exchange
 * @param pds array of planchet details of the planchet to withdraw
 * @param pds_length number of entries in the @a pds array
 * @param reserve_priv private key of the reserve to withdraw from
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_BatchWithdraw2Handle *
TALER_EXCHANGE_batch_withdraw2 (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int pds_length,
  const struct TALER_PlanchetDetail pds[static pds_length],
  TALER_EXCHANGE_BatchWithdraw2Callback res_cb,
  void *res_cb_cls);
```

### Differences

| batch_withdraw                     | batch_withdraw2        |
|------------------------------------|------------------------|
| `TALER_EXCHANGE_WithdrawCoinInput` | `TALER_PlanchetDetail` |


```
struct TALER_EXCHANGE_WithdrawCoinInput
{
  /**
   * Denomination of the coin.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Master key material for the coin.
   */
  const struct TALER_PlanchetMasterSecretP *ps;

  /**
   * Age commitment for the coin.
   */
  const struct TALER_AgeCommitmentHash *ach;

};
```


```
struct TALER_PlanchetDetail
{
  /**
   * Hash of the denomination public key.
   */
  struct TALER_DenominationHashP denom_pub_hash;

  /**
   * The blinded planchet
   */
  struct TALER_BlindedPlanchet {
      /**
       * Type of the sign blinded message
       */
      enum TALER_DenominationCipher cipher;

      /**
       * Details, depending on @e cipher.
       */
      union
      {
        /**
         * If we use #TALER_DENOMINATION_CS in @a cipher.
         */
        struct TALER_BlindedCsPlanchet cs_blinded_planchet;

        /**
         * If we use #TALER_DENOMINATION_RSA in @a cipher.
         */
        struct TALER_BlindedRsaPlanchet rsa_blinded_planchet;

      } details;
  } blinded_planchet;
};

```



## TODOs

### Update documentation

- [x] batch-withdraw needs error code for AgeRestrictionRequired
- [x] withdraw needs error code for AgeRestrictionRequired


