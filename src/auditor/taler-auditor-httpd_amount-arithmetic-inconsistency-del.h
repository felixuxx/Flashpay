#ifndef SRC_TALER_AUDITOR_HTTPD_AMOUNT_ARITHMETIC_INCONSISTENCY_DEL_H
#define SRC_TALER_AUDITOR_HTTPD_AMOUNT_ARITHMETIC_INCONSISTENCY_DEL_H

#include <microhttpd.h>
#include "taler-auditor-httpd.h"

/**
 * Initialize subsystem.
 */
void
TEAH_AMOUNT_ARITHMETIC_INCONSISTENCY_DELETE_init (void);

/**
 * Shut down subsystem.
 */
void
TEAH_AMOUNT_ARITHMETIC_INCONSISTENCY_DELETE_done (void);

/**
 * Handle a "/deposit-confirmation" request.  Parses the JSON, and, if
 * successful, checks the signatures and stores the result in the DB.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
MHD_RESULT
TAH_AMOUNT_ARITHMETIC_INCONSISTENCY_handler_delete (struct
                                                    TAH_RequestHandler *rh,
                                                    struct MHD_Connection *
                                                    connection,
                                                    void **connection_cls,
                                                    const char *upload_data,
                                                    size_t *upload_data_size,
                                                    const char *const args[]);


#endif // SRC_TALER_AUDITOR_HTTPD_AMOUNT_ARITHMETIC_INCONSISTENCY_DEL_H