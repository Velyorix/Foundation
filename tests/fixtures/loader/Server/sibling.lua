-- selene: allow(unscoped_variables, unused_variable)
-- Package-level global on purpose: the loader spec checks that files share one environment.
LOAD_COUNT = (LOAD_COUNT or 0) + 1
return "server-sibling"
