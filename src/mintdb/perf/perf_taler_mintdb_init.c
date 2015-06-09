#include <gnunet/platform.h>
#include <gnunet/gnunet_crypto_lib.h>
#include <gnunet/gnunet_signatures.h>

#include <taler/taler_mintdb_plugin.h>
#include <taler/taler_signatures.h>
#include <taler/taler_amount_lib.h>


#define CURRENCY "EUR\0\0\0\0\0\0\0\0"

struct TALER_MINTDB_CollectableBlindcoin *
init_CollectableBlindcoin(){
    struct TALER_MINTDB_CollectableBlindcoin *coin = GNUNET_malloc(sizeof(*coin));
    
    struct GNUNET_CRYPTO_EddsaPrivateKey *reserve_sig_key  = GNUNET_CRYPTO_eddsa_key_create();
    struct GNUNET_CRYPTO_rsa_PrivateKey  *denomination_key = GNUNET_CRYPTO_rsa_private_key_create(512);

    
    coin->denom_pub.rsa_public_key = GNUNET_CRYPTO_rsa_private_key_get_public(denomination_key);
    GNUNET_CRYPTO_eddsa_key_get_public(reserve_sig_key, &(coin->reserve_pub.eddsa_pub));
    
    
    //TODO Randomise the amount that is deposited and apply a fee subsequently
    
    coin->amount_with_fee = (struct TALER_Amount) {1, 1, CURRENCY};
    coin->withdraw_fee    = (struct TALER_Amount) {0, 1, CURRENCY};


    int random_int = rand();
    coin->sig.rsa_signature = GNUNET_CRYPTO_rsa_sign(denomination_key, &random_int, sizeof(random_int));
    GNUNET_CRYPTO_hash_create_random(GNUNET_CRYPTO_QUALITY_WEAK , &(coin->h_coin_envelope));

    void *purpose = GNUNET_malloc(sizeof(struct GNUNET_CRYPTO_EccSignaturePurpose) + sizeof(int));
    ((struct GNUNET_CRYPTO_EccSignaturePurpose *)purpose)->size = sizeof(struct GNUNET_CRYPTO_EccSignaturePurpose) + sizeof(int);
    ((struct GNUNET_CRYPTO_EccSignaturePurpose *)purpose)->purpose = GNUNET_SIGNATURE_PURPOSE_TEST;
    *((int *)(purpose + sizeof(struct GNUNET_CRYPTO_EccSignaturePurpose))) = random_int;

    GNUNET_CRYPTO_eddsa_sign(reserve_sig_key, purpose, &coin->reserve_sig.eddsa_signature);


    
    GNUNET_free(reserve_sig_key);
    GNUNET_CRYPTO_rsa_private_key_free(denomination_key);
    return coin;
}


struct TALER_MINTDB_Reserve *
init_Reserve(){
    struct TALER_MINTDB_Reserve *reserve = GNUNET_malloc(sizeof(*reserve));
    struct GNUNET_CRYPTO_EddsaPrivateKey *reserve_priv = GNUNET_CRYPTO_eddsa_key_create();

    GNUNET_CRYPTO_eddsa_key_get_public(reserve_priv , &(reserve->pub.eddsa_pub));
    

    reserve->balance = (struct TALER_Amount){1, 1, CURRENCY};
    reserve->expiry = GNUNET_TIME_absolute_get_forever_();
    
    GNUNET_free(reserve_priv);
    return reserve;
}


struct TALER_MINTDB_RefreshSession *
init_Refresh_session(){
    struct TALER_MINTDB_RefreshSession *refresh_session = GNUNET_malloc(sizeof(*refresh_session));

    refresh_session->noreveal_index = 1;
    refresh_session->num_oldcoins = 1;
    refresh_session->num_newcoins = 1;

    return refresh_session;
}


struct TALER_MINTDB_Deposit *
init_Deposit(){
    static int transaction_id = 0;

    struct TALER_MINTDB_Deposit *deposit = GNUNET_malloc(sizeof(*deposit));

    deposit-> transaction_id = transaction_id;
    transaction_id++;
    

    //TODO Randomize the amount that is deposited

    deposit->amount_with_fee = (struct TALER_Amount) {1, 1, CURRENCY};
    deposit->deposit_fee = (struct TALER_Amount) {0, 1, CURRENCY};

    deposit->timestamp = GNUNET_TIME_absolute_get();
    deposit->refund_deadline = GNUNET_TIME_absolute_get();

    GNUNET_CRYPTO_hash_create_random(GNUNET_CRYPTO_QUALITY_WEAK, &deposit->h_contract);
    GNUNET_CRYPTO_hash_create_random(GNUNET_CRYPTO_QUALITY_WEAK, &deposit->h_wire);
    
    // Coin Spend Signature
    {
        struct GNUNET_CRYPTO_EddsaSignature sig;
        
        struct GNUNET_CRYPTO_EddsaPrivateKey *p_eddsa_prvt = GNUNET_CRYPTO_eddsa_key_create();
        void *prp = GNUNET_malloc(sizeof(struct GNUNET_CRYPTO_EccSignaturePurpose)+sizeof(int));
        *((struct GNUNET_CRYPTO_EccSignaturePurpose *)prp) =(struct GNUNET_CRYPTO_EccSignaturePurpose) {sizeof(struct GNUNET_CRYPTO_EccSignaturePurpose)+sizeof(int), GNUNET_SIGNATURE_PURPOSE_TEST};


        GNUNET_CRYPTO_eddsa_sign(p_eddsa_prvt, (struct GNUNET_CRYPTO_EccSignaturePurpose *) prp, &sig);

        deposit->csig.eddsa_signature = sig;

        GNUNET_free(p_eddsa_prvt);
    }

    // Merchant Key
    {
        struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
        struct GNUNET_CRYPTO_EddsaPrivateKey *p_eddsa_prv = GNUNET_CRYPTO_eddsa_key_create();

        GNUNET_CRYPTO_eddsa_key_get_public(p_eddsa_prv, &eddsa_pub);
        
        deposit->merchant_pub.eddsa_pub = eddsa_pub;
           
        GNUNET_free(p_eddsa_prv);
    }

    // Coin 
    {
        

        {
            struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
            struct GNUNET_CRYPTO_EddsaPrivateKey *p_eddsa_prvt = GNUNET_CRYPTO_eddsa_key_create();
        
            GNUNET_CRYPTO_eddsa_key_get_public(p_eddsa_prvt, &eddsa_pub);
        
            deposit->coin.coin_pub.eddsa_pub = eddsa_pub;
            
            GNUNET_free(p_eddsa_prvt);
        }

        {
            struct GNUNET_CRYPTO_rsa_PrivateKey *p_rsa_prv = GNUNET_CRYPTO_rsa_private_key_create(128);
            struct GNUNET_CRYPTO_rsa_PublicKey *p_rsa_pub = GNUNET_CRYPTO_rsa_private_key_get_public(p_rsa_prv);
            
            deposit->coin.denom_pub.rsa_public_key = p_rsa_pub;
            
            

            deposit->coin.denom_sig.rsa_signature = GNUNET_CRYPTO_rsa_sign(p_rsa_prv, 
                                                            (void *) &(deposit->coin.coin_pub.eddsa_pub), 
                                                            sizeof(&(deposit->coin.coin_pub.eddsa_pub)));

            GNUNET_CRYPTO_rsa_private_key_free(p_rsa_prv);
        }       

    }

   
    return deposit;
}


struct TALER_MINTDB_DenominationKeyIssueInformation *
init_denomination(){
  struct TALER_MINTDB_DenominationKeyIssueInformation *dki = GNUNET_malloc(sizeof(&dki));


  dki->denom_priv.rsa_private_key
    = GNUNET_CRYPTO_rsa_private_key_create (128);
  GNUNET_assert (NULL != dki->denom_priv.rsa_private_key);
  dki->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
      &dki->issue.denom_hash);

  struct GNUNET_CRYPTO_EddsaPrivateKey *master_prvt = 
    GNUNET_CRYPTO_eddsa_key_create();

  struct GNUNET_CRYPTO_EddsaPublicKey master_pub;

  GNUNET_CRYPTO_eddsa_key_get_public(master_prvt, &master_pub);
  dki->issue.master.eddsa_pub = master_pub;

  struct GNUNET_TIME_Absolute anchor = GNUNET_TIME_absolute_get();

  dki->issue.start = GNUNET_TIME_absolute_hton (anchor);
  dki->issue.expire_withdraw =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
          GNUNET_TIME_relative_get_hour_()));
  dki->issue.expire_spend =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
          GNUNET_TIME_relative_get_hour_()));
  dki->issue.expire_legal =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
          GNUNET_TIME_relative_get_hour_()));

  struct TALER_Amount amount = {.value = 1, .fraction = 1, .currency = CURRENCY};

  TALER_amount_hton (&dki->issue.value, &amount);
  TALER_amount_hton (&dki->issue.fee_withdraw, &amount);
  TALER_amount_hton (&dki->issue.fee_deposit, &amount);
  TALER_amount_hton (&dki->issue.fee_refresh, &amount);
  dki->issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  dki->issue.purpose.size = htonl (sizeof (struct TALER_MINTDB_DenominationKeyIssueInformation) -
      offsetof (struct TALER_MINTDB_DenominationKeyIssueInformation,
        issue.purpose));
  GNUNET_assert (GNUNET_OK ==
      GNUNET_CRYPTO_eddsa_sign (master_prvt,
        &dki->issue.purpose,
        &dki->issue.signature.eddsa_signature));

  return dki;
}







// Destructors


int
free_deposit(struct TALER_MINTDB_Deposit *deposit){
  GNUNET_free(deposit->coin.denom_pub.rsa_public_key);
  GNUNET_free(deposit->coin.denom_sig.rsa_signature);
  
  GNUNET_free(deposit);

  return GNUNET_OK;
}


int
free_coin(struct TALER_MINTDB_CollectableBlindcoin *coin){
  GNUNET_free(coin->sig.rsa_signature);
  GNUNET_free(coin->denom_pub.rsa_public_key);

  GNUNET_free(coin);

  return GNUNET_OK;
}


int
free_denomination(struct TALER_MINTDB_DenominationKeyIssueInformation *dki){
  GNUNET_free(dki->denom_priv.rsa_private_key);
  GNUNET_free(dki->denom_pub.rsa_public_key);

  GNUNET_free(dki);
  
  return GNUNET_OK;
}




