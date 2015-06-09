#ifndef __PERF_TALER_MINTDB_INTERPRETER_H__
#define __PERF_TALER_MINTDB_INTERPRETER_H__

#include <sys/time.h>

#include <gnunet/platform.h>
#include <taler/taler_mintdb_lib.h>
#include <taler/taler_mintdb_plugin.h>



#define INIT_CMD_LOOP(label, _iter) {.command = CMD_LOOP, .name = label, .details.loop = {.max_iterations = _iter, .curr_iteration = -1} }

#define INIT_CMD_END_LOOP(label, _loopname) {.command = CMD_END_LOOP, .name = label, .details.end_loop.loop_start = _loopname}

#define INIT_CMD_END(label) {.command = CMD_END, .name = label}

#define INIT_CMD_GET_TIME(label) {.command = CMD_GET_TIME, .name = label}

#define INIT_CMD_GAUGER(label, _start_time, _stop_time, _description) {.command = CMD_GAUGER, .name = label, .details.gauger = {.start_time = _start_time, .end_time = _endtime, .description = _description} }

#define INIT_CMD_START_TRANSACTION(label) {.command = CMD_START_TRANSACTION, .name = label}

#define INIT_CMD_COMMIT_TRANSACTION(label) {.command = CMD_COMMIT_TRANSACTION, .name = label}



#define INIT_CMD_INSERT_DEPOSIT(label) {.command = CMD_INSERT_DEPOSIT, .name = label}

#define INIT_CMD_GET_DEPOSIT(label, _saved) {.command = CMD_GET_DEPOSIT, .name = label, .details.get_deposit.saved = _source }

#define INIT_CMD_SAVE_DEPOSIT(label, _loop, _save, _nb) {.command = CMD_SAVE_ARRAY, .name = label, .details.save_array = {.loop = _loop, .nb = _nb, .saved = _save, saved_type = DEPOSIT} }

#define INIT_CMD_LOAD_DEPOSIT(label, _loop, _save, _nb) {.command = CMD_LOAD_ARRAY, .name = label, .details.load_array = {.loop = _loop, .nb = _nb, .saved = _save} }



enum PERF_TALER_MINTDB_TYPE {
  DEPOSIT,
  TIME,
};

/**
 * Command to be interpreted.
 *
 */
struct PERF_TALER_MINTDB_CMD{

    enum {

        // Define the start of al command chain loop
        CMD_LOOP,
        // Define the end of a command chain loop
        CMD_END_LOOP,

        // All comand chain must hace this as their last command
        CMD_END,

        // Save the time at which the command was executed
        CMD_GET_TIME,

        // Upload performance to Gauger
        CMD_GAUGER,

        // Start a database transaction
        CMD_START_TRANSACTION,

        // End a database transaction
        CMD_COMMIT_TRANSACTION,

        // Insert a deposit into the database
        CMD_INSERT_DEPOSIT,

        // Check if a deposit is in the database
        CMD_GET_DEPOSIT,

        // Saves random deposits from a loop
        CMD_SAVE_ARRAY,

        // Load deposits saved earlyer
        CMD_LOAD_ARRAY,

    } command;

    char name[40];

    // Contains command specific data.
    union {
        struct {
            const int max_iterations;
            int curr_iteration;
        } loop;

        struct {
            char loop_start[40];
        } end_loop;

        struct {
            char start_time[40];
            char stop_time[40];

            char description[40];
        } gauger; 

        struct {
            int nb; // Number of deposits to save
            int index; // The number of deposits already saved
            char loop[40]; // The loop from which the data will be extracted
            char saved[40]; // The deposit saved
            enum PERF_TALER_MINTDB_TYPE saved_type;
            union {
              struct TALER_MINTDB_Deposit **deposit;
              struct timespec *time;
            } saved_data;
        } save_array;

        struct {
            int nb; //the number of deposits to save
            char loop[40];
            char saved[40]; // The command where the deposit were saved
            enum PERF_TALER_MINTDB_TYPE loaded_type; 
            unsigned int *permutation; // A permutation array to randomize the order the deposits are loaded in
        } load_array;

        struct {
            char source[40];
        } get_deposit;


    } details;
    union {
        struct TALER_MINTDB_Deposit *deposit;
        struct timespec time;
    } exposed; 

    int exposed_used;
};


int
PERF_TALER_MINTDB_interprete(
    struct TALER_MINTDB_Plugin *db_plugin,
    struct TALER_MINTDB_Session *session,
    struct PERF_TALER_MINTDB_CMD cmd[]);


#endif
