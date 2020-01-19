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
 * @file include/testing_api_cmd_exec_client.h
 * @brief test commands aimed to call the CLI twister client
 *        to drive its behaviour.
 * @author Christian Grothoff <christian@grothoff.org>
 * @author Marcello Stanisci
 */

#include "platform.h"
#include <taler/taler_testing_lib.h>
#include "taler_twister_testing_lib.h"


/**
 * State for a "modify object" CMD.
 */
struct ModifyObjectState
{
  /**
   * Process handle for the twister CLI client.
   */
  struct GNUNET_OS_Process *proc;

  /**
   * Object-like notation to the object to delete.
   */
  const char *path;


  /**
   * Value to substitute to the original one.
   */
  const char *value;

  /**
   * Config file name to pass to the CLI client.
   */
  const char *config_filename;
};


/**
 * State for a "flip object" CMD.
 */
struct FlipObjectState
{
  /**
   * Process handle for the twister CLI client.
   */
  struct GNUNET_OS_Process *proc;

  /**
   * Object-like notation to the string-object to flip.
   */
  const char *path;

  /**
   * Config file name to pass to the CLI client.
   */
  const char *config_filename;
};


/**
 * State for a "delete object" CMD.
 */
struct DeleteObjectState
{
  /**
   * Process handle for the twister CLI client.
   */
  struct GNUNET_OS_Process *proc;

  /**
   * Object-like notation to the object to delete.
   */
  const char *path;

  /**
   * Config file name to pass to the CLI client.
   */
  const char *config_filename;
};


/**
 * State for a "malform request" CMD.
 */
struct MalformRequestState
{
  /**
   * Process handle for the twister CLI client.
   */
  struct GNUNET_OS_Process *proc;

  /**
   * Config file name to pass to the CLI client.
   */
  const char *config_filename;
};


/**
 * State for a "malform response" CMD.
 */
struct MalformResponseState
{
  /**
   * Process handle for the twister CLI client.
   */
  struct GNUNET_OS_Process *proc;

  /**
   * Config file name to pass to the CLI client.
   */
  const char *config_filename;
};


/**
 * State for a "hack response code" CMD.
 */
struct HackResponseCodeState
{
  /**
   * Process handle for the twister CLI client.
   */
  struct GNUNET_OS_Process *proc;

  /**
   * HTTP status code to substitute to the original one.
   */
  unsigned int http_status;

  /**
   * Config file name to pass to the CLI client.
   */
  const char *config_filename;
};


/**
 * Free the state from a "hack response code" CMD, and
 * possibly kill its process if it did not terminate yet.
 *
 * @param cls closure.
 * @param cmd the command being cleaned up.
 */
static void
hack_response_code_cleanup
  (void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct HackResponseCodeState *hrcs = cls;

  if (NULL != hrcs->proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (hrcs->proc,
                                               SIGKILL));
    GNUNET_OS_process_wait (hrcs->proc);
    GNUNET_OS_process_destroy (hrcs->proc);
    hrcs->proc = NULL;
  }
  GNUNET_free (hrcs);
}


/**
 * Offer data internal to a "hack response code" CMD,
 * to other commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
hack_response_code_traits (void *cls,
                           const void **ret,
                           const char *trait,
                           unsigned int index)
{

  struct HackResponseCodeState *hrcs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &hrcs->proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run a "hack response code" CMD.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
hack_response_code_run (void *cls,
                        const struct TALER_TESTING_Command *cmd,
                        struct TALER_TESTING_Interpreter *is)
{
  struct HackResponseCodeState *hrcs = cls;
  char *http_status;

  GNUNET_asprintf (&http_status, "%u",
                   hrcs->http_status);

  hrcs->proc = GNUNET_OS_start_process
                 (GNUNET_NO,
                 GNUNET_OS_INHERIT_STD_ALL,
                 NULL, NULL, NULL,
                 "taler-twister",
                 "taler-twister",
                 "-c", hrcs->config_filename,
                 "--responsecode", http_status,
                 NULL);
  if (NULL == hrcs->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
  GNUNET_free (http_status);
}


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
                                      unsigned int http_status)
{
  struct HackResponseCodeState *hrcs;

  hrcs = GNUNET_new (struct HackResponseCodeState);
  hrcs->http_status = http_status;
  hrcs->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &hack_response_code_run,
    .cleanup = &hack_response_code_cleanup,
    .traits = &hack_response_code_traits,
    .cls = hrcs
  };

  return cmd;
}


/**
 * Free the state from a "delete object" CMD, and
 * possibly kill its process if it did not terminate yet.
 *
 * @param cls closure.
 * @param cmd the command being cleaned up.
 */
static void
delete_object_cleanup
  (void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct DeleteObjectState *dos = cls;

  if (NULL != dos->proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (dos->proc,
                                               SIGKILL));
    GNUNET_OS_process_wait (dos->proc);
    GNUNET_OS_process_destroy (dos->proc);
    dos->proc = NULL;
  }
  GNUNET_free (dos);
}


/**
 * Offer data internal to a "delete object" CMD,
 * to other commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
delete_object_traits (void *cls,
                      const void **ret,
                      const char *trait,
                      unsigned int index)
{

  struct DeleteObjectState *dos = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &dos->proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run a "delete object" CMD.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
delete_object_run (void *cls,
                   const struct TALER_TESTING_Command *cmd,
                   struct TALER_TESTING_Interpreter *is)
{
  struct DeleteObjectState *dos = cls;

  dos->proc = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-twister",
                                       "taler-twister",
                                       "-c", dos->config_filename,
                                       "--deleteobject", dos->path,
                                       NULL);
  if (NULL == dos->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state from a "modify object" CMD, and
 * possibly kill its process if it did not terminate yet.
 *
 * @param cls closure.
 * @param cmd the command being cleaned up.
 */
static void
modify_object_cleanup
  (void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct ModifyObjectState *mos = cls;

  if (NULL != mos->proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (mos->proc,
                                               SIGKILL));
    GNUNET_OS_process_wait (mos->proc);
    GNUNET_OS_process_destroy (mos->proc);
    mos->proc = NULL;
  }
  GNUNET_free (mos);
}


/**
 * Offer data internal to a "modify object" CMD,
 * to other commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
modify_object_traits (void *cls,
                      const void **ret,
                      const char *trait,
                      unsigned int index)
{

  struct ModifyObjectState *mos = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &mos->proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run a "modify object" CMD.  The "download fashion" of it.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
modify_object_dl_run (void *cls,
                      const struct TALER_TESTING_Command *cmd,
                      struct TALER_TESTING_Interpreter *is)
{
  struct ModifyObjectState *mos = cls;

  mos->proc = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-twister",
                                       "taler-twister",
                                       "-c", mos->config_filename,
                                       "-m", mos->path,
                                       "--value", mos->value,
                                       NULL);
  if (NULL == mos->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Run a "modify object" CMD, the "upload fashion" of it.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
modify_object_ul_run (void *cls,
                      const struct TALER_TESTING_Command *cmd,
                      struct TALER_TESTING_Interpreter *is)
{
  struct ModifyObjectState *mos = cls;

  mos->proc = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-twister",
                                       "taler-twister",
                                       "-c", mos->config_filename,
                                       "-X", mos->path,
                                       "--value", mos->value,
                                       NULL);
  if (NULL == mos->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


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
                                 const char *path)
{
  struct DeleteObjectState *dos;

  dos = GNUNET_new (struct DeleteObjectState);
  dos->path = path;
  dos->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &delete_object_run,
    .cleanup = &delete_object_cleanup,
    .traits = &delete_object_traits,
    .cls = dos
  };

  return cmd;
}


/**
 * Free the state from a "flip object" CMD, and
 * possibly kill its process if it did not terminate yet.
 *
 * @param cls closure.
 * @param cmd the command being cleaned up.
 */
static void
flip_object_cleanup
  (void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct FlipObjectState *fos = cls;

  if (NULL != fos->proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (fos->proc,
                                               SIGKILL));
    GNUNET_OS_process_wait (fos->proc);
    GNUNET_OS_process_destroy (fos->proc);
    fos->proc = NULL;
  }
  GNUNET_free (fos);
}


/**
 * Offer data internal to a "flip object" CMD,
 * to other commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
flip_object_traits (void *cls,
                    const void **ret,
                    const char *trait,
                    unsigned int index)
{

  struct FlipObjectState *fos = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &fos->proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run a "flip object" CMD, the upload fashion of it.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
flip_upload_run (void *cls,
                 const struct TALER_TESTING_Command *cmd,
                 struct TALER_TESTING_Interpreter *is)
{
  struct FlipObjectState *fos = cls;

  fos->proc = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-twister",
                                       "taler-twister",
                                       "-c", fos->config_filename,
                                       "--flip-ul", fos->path,
                                       NULL);
  if (NULL == fos->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Run a "flip object" CMD, the download fashion of it.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
flip_download_run (void *cls,
                   const struct TALER_TESTING_Command *cmd,
                   struct TALER_TESTING_Interpreter *is)
{
  struct FlipObjectState *fos = cls;

  fos->proc = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-twister",
                                       "taler-twister",
                                       "-c", fos->config_filename,
                                       "--flip-dl", fos->path,
                                       NULL);
  if (NULL == fos->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


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
                               const char *path)
{
  struct FlipObjectState *dos;

  dos = GNUNET_new (struct FlipObjectState);
  dos->path = path;
  dos->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &flip_upload_run,
    .cleanup = &flip_object_cleanup,
    .traits = &flip_object_traits,
    .cls = dos
  };

  return cmd;
}


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
                                 const char *path)
{
  struct FlipObjectState *dos;

  dos = GNUNET_new (struct FlipObjectState);
  dos->path = path;
  dos->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &flip_download_run,
    .cleanup = &flip_object_cleanup,
    .traits = &flip_object_traits,
    .cls = dos
  };

  return cmd;
}


/**
 * Free the state from a "malform request" CMD, and
 * possibly kill its process if it did not terminate yet.
 *
 * @param cls closure.
 * @param cmd the command being cleaned up.
 */
static void
malform_request_cleanup (void *cls,
                         const struct TALER_TESTING_Command *cmd)
{
  struct MalformRequestState *mrs = cls;

  if (NULL != mrs->proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (mrs->proc,
                                               SIGKILL));
    GNUNET_OS_process_wait (mrs->proc);
    GNUNET_OS_process_destroy (mrs->proc);
    mrs->proc = NULL;
  }
  GNUNET_free (mrs);
}


/**
 * Offer data internal to a "malform request" CMD,
 * to other commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
malform_request_traits (void *cls,
                        const void **ret,
                        const char *trait,
                        unsigned int index)
{
  struct MalformRequestState *mrs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &mrs->proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run a "malform request" CMD.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
malform_request_run (void *cls,
                     const struct TALER_TESTING_Command *cmd,
                     struct TALER_TESTING_Interpreter *is)
{
  struct MalformRequestState *mrs = cls;

  mrs->proc = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-twister",
                                       "taler-twister",
                                       "-c", mrs->config_filename,
                                       "--malformupload",
                                       NULL);
  if (NULL == mrs->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state from a "malform response" CMD, and
 * possibly kill its process if it did not terminate yet.
 *
 * @param cls closure.
 * @param cmd the command being cleaned up.
 */
static void
malform_response_cleanup
  (void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct MalformResponseState *mrs = cls;

  if (NULL != mrs->proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (mrs->proc,
                                               SIGKILL));
    GNUNET_OS_process_wait (mrs->proc);
    GNUNET_OS_process_destroy (mrs->proc);
    mrs->proc = NULL;
  }
  GNUNET_free (mrs);
}


/**
 * Offer data internal to a "malform response" CMD,
 * to other commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
malform_response_traits (void *cls,
                         const void **ret,
                         const char *trait,
                         unsigned int index)
{
  struct MalformResponseState *mrs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &mrs->proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run a "malform response" CMD.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
malform_response_run (void *cls,
                      const struct TALER_TESTING_Command *cmd,
                      struct TALER_TESTING_Interpreter *is)
{
  struct MalformResponseState *mrs = cls;

  mrs->proc = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-twister",
                                       "taler-twister",
                                       "-c", mrs->config_filename,
                                       "--malform",
                                       NULL);
  if (NULL == mrs->proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


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
                                   const char *config_filename)
{
  struct MalformRequestState *mrs;

  mrs = GNUNET_new (struct MalformRequestState);
  mrs->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &malform_request_run,
    .cleanup = &malform_request_cleanup,
    .traits = &malform_request_traits,
    .cls = mrs
  };

  return cmd;
}


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
                                    const char *config_filename)
{
  struct MalformResponseState *mrs;

  mrs = GNUNET_new (struct MalformResponseState);
  mrs->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &malform_response_run,
    .cleanup = &malform_response_cleanup,
    .traits = &malform_response_traits,
    .cls = mrs
  };

  return cmd;

}


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
                                    const char *value)
{
  struct ModifyObjectState *mos;

  mos = GNUNET_new (struct ModifyObjectState);
  mos->path = path;
  mos->value = value;
  mos->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &modify_object_dl_run,
    .cleanup = &modify_object_cleanup,
    .traits = &modify_object_traits,
    .cls = mos
  };

  return cmd;
}


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
                                    const char *value)
{
  struct ModifyObjectState *mos;

  mos = GNUNET_new (struct ModifyObjectState);
  mos->path = path;
  mos->value = value;
  mos->config_filename = config_filename;

  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &modify_object_ul_run,
    .cleanup = &modify_object_cleanup,
    .traits = &modify_object_traits,
    .cls = mos
  };

  return cmd;
}


/* end of testing_api_cmd_exec_client.c */
