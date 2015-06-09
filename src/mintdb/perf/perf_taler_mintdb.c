#include "perf_taler_mintdb_interpreter.h"





int
main(int argc, char ** argv)
{
 
  struct PERF_TALER_MINTDB_CMD test[] = 
  {
    INIT_CMD_LOOP("loop_db_init_deposit",100000),
    INIT_CMD_START_TRANSACTION("start_transaction_init"),
    INIT_CMD_INSERT_DEPOSIT("init_deposit_insert"),
    INIT_CMD_COMMIT_TRANSACTION("commit_transaction_init"),
    INIT_CMD_END_LOOP("endloop_init_deposit","loop_db_init_deposit"),


    INIT_CMD_END("end")
  };

  struct GNUNET_CONFIGURATION_Handle *config = GNUNET_CONFIGURATION_create();

  // FIXME Add data to the config handler to be able to connect to the database

  struct TALER_MINTDB_Plugin *plugin = TALER_MINTDB_plugin_load(config);
  struct TALER_MINTDB_Session *session = plugin->get_session(plugin->cls, GNUNET_YES);

  plugin->create_tables(plugin->cls, GNUNET_YES);


  PERF_TALER_MINTDB_interprete(plugin, session, test);


  plugin->drop_temporary(plugin->cls, session);

  // Free the session ??

  TALER_MINTDB_plugin_unload(plugin);
  return GNUNET_OK;
}
