#ifndef __PERF_TALER_MINTDB_INIT_H___
#define __PERF_TALER_MINTDB_INIT_H___


#include <gnunet/platform.h>

#include <taler/taler_mintdb_lib.h>
#include <taler/taler_mintdb_plugin.h>


#define CURRENCY "EUR\0\0\0\0\0\0\0\0"


struct TALER_MINTDB_CollectableBlindcoin *
init_collectableBlindcoin();

struct TALER_MINTDB_RefreshSession *
init_refresh_session();

struct TALER_MINTDB_Deposit *
init_deposit(int transaction_id);

struct TALER_MINTDB_DenominationKeyIssueInformation *
init_denomination();



int
free_deposit(struct TALER_MINTDB_Deposit *deposit);

int
free_collectableBlindcoin(struct TALER_MINTDB_CollectableBlindcoin);

int 
free_denomination(struct TALER_MINTDB_DenominationKeyIssueInformation *dki);


#endif
