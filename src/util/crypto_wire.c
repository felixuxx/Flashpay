/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file util/crypto_wire.c
 * @brief functions for making and verifying /wire account signatures
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


void
TALER_merchant_wire_signature_hash (const char *payto_uri,
                                    const struct TALER_WireSaltP *salt,
                                    struct TALER_MerchantWireHashP *hc)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (hc,
                                    sizeof (*hc),
                                    salt,
                                    sizeof (*salt),
                                    payto_uri,
                                    strlen (payto_uri) + 1,
                                    "merchant-wire-signature",
                                    strlen ("merchant-wire-signature"),
                                    NULL, 0));
}


/* end of crypto_wire.c */
