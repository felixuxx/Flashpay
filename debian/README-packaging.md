This file contains some notes about packaging.

## Systemd Units

The main unit file is taler-exchange.service.  It is a unit that does not run
anything, but instead can be used to stop/start all exchange-related services
at once.
