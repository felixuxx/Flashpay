#include "taler-auditor-httpd_amount-arithmetic-inconsistency-del.h"


MHD_RESULT
TAH_AMOUNT_ARITHMETIC_INCONSISTENCY_handler_delete (struct
                                                    TAH_RequestHandler *rh,
                                                    struct MHD_Connection *
                                                    connection,
                                                    void **connection_cls,
                                                    const char *upload_data,
                                                    size_t *upload_data_size,
                                                    const char *const args[])
{

  enum GNUNET_DB_QueryStatus qs;

  uint64_t row_id;

  if (args[2] != NULL)
    row_id = atoi (args[2]);
  else
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "row could not be found");

  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }


  // execute the transaction
  qs = TAH_plugin->delete_amount_arithmetic_inconsistency (TAH_plugin->cls,
                                                           row_id);

  if (0 > qs)
  {
    // goes in here if there was an error with the transaction
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    TALER_LOG_WARNING (
      "Failed to handle DELETE /amount-arithmetic-inconsistency/ %s\n",
      args[1]);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "row could not be found");

  }

  // on success?
  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_NO_CONTENT,
                                    GNUNET_JSON_pack_string ("status",
                                                             "AMOUNT_ARITHMETIC_INCONSISTENCY_OK"));

}