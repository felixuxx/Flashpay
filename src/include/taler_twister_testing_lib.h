/*
  This file is part of TALER
  (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file include/taler_twister_testing_lib.h
 * @brief API for using twister-dependant test commands.
 * @author Christian Grothoff <christian@grothoff.org>
 * @author Marcello Stanisci
 */
#ifndef TALER_TWISTER_TESTING_LIB_H
#define TALER_TWISTER_TESTING_LIB_H

#include <taler/taler_testing_lib.h>

#define TWISTER_FAIL() \
  do {GNUNET_break (0); return NULL; } while (0)

/**
 * Define a "hack response code" CMD.  This causes the next
 * response code (from the service proxied by the twister) to
 * be substituted with @a http_status.
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @param http_status new response code to use
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_hack_response_code (const char *label,
                                      const char *config_filename,
                                      unsigned int http_status);

/**
 * Create a "delete object" CMD.  This command deletes
 * the JSON object pointed by @a path.
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @param path object-like path notation to point the object
 *        to delete.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_delete_object (const char *label,
                                 const char *config_filename,
                                 const char *path);

/**
 * Create a "modify object" CMD.  This command instructs
 * the twister to modify the next object that is downloaded
 * from the proxied service.
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @param path object-like path notation to point the object
 *        to modify.
 * @param value value to put as the object's.
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_modify_object_dl (const char *label,
                                    const char *config_filename,
                                    const char *path,
                                    const char *value);

/**
 * Create a "modify object" CMD.  This command instructs
 * the twister to modify the next object that will be uploaded
 * to the proxied service.
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @param path object-like path notation pointing the object
 *        to modify.
 * @param value value to put as the object's.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_modify_object_ul (const char *label,
                                    const char *config_filename,
                                    const char *path,
                                    const char *value);


/**
 * Create a "modify header" CMD.  This command instructs
 * the twister to modify a header in the next HTTP response.
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @param path path identifying where to modify.
 * @param value value to set the header to.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_modify_header_dl (const char *label,
                                    const char *config_filename,
                                    const char *path,
                                    const char *value);


/**
 * Create a "malform response" CMD.  This command makes
 * the next response randomly malformed (by truncating it).
 *
 * @param label command label
 * @param config_filename configuration filename.
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_malform_response (const char *label,
                                    const char *config_filename);

/**
 * Create a "malform request" CMD.  This command makes the
 * next request randomly malformed (by truncating it).
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_malform_request (const char *label,
                                   const char *config_filename);

/**
 * Define a "flip object" command, for objects to upload.
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @param path object-like path notation to point the object
 *        to flip.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_flip_upload (const char *label,
                               const char *config_filename,
                               const char *path);


/**
 * Define a "flip object" command, for objects to download.
 *
 * @param label command label
 * @param config_filename configuration filename.
 * @param path object-like path notation to point the object
 *        to flip.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_flip_download (const char *label,
                                 const char *config_filename,
                                 const char *path);

#endif
