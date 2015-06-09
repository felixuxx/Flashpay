#ifndef __PERF_TALER_MINTDB_INIT_H___
#define __PERF_TALER_MINTDB_INIT_H___


#include <gnunet/platform.h>

#include <taler/taler_mintdb_lib.h>
#include <taler/taler_mintdb_plugin.h>


#define CURRENCY "EUR"


struct TALER_MINTDB_CollectableBlindcoin *
init_collectable_blindcoin(void);

struct TALER_MINTDB_RefreshSession *
init_refresh_session(void);

struct TALER_MINTDB_Deposit *
init_deposit(int transaction_id);

struct TALER_MINTDB_DenominationKeyIssueInformation *
init_denomination(void);



int
free_deposit(struct TALER_MINTDB_Deposit *deposit);

int
free_collectable_blindcoin(struct TALER_MINTDB_CollectableBlindcoin *NAME);

int
free_denomination(struct TALER_MINTDB_DenominationKeyIssueInformation *dki);


#endif
