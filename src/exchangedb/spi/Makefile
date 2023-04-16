EXTENSION = own_test
MODULES = own_test
DATA = own_test.sql
PG_CPPFLAGS = -I /usr/include/postgresql

# postgresql build stuff
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
