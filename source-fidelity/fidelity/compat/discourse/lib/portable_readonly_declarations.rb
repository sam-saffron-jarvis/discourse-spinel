require_relative "portable_readonly_state"
class PortableReadonlyState
LAST_POSTGRES_READONLY_KEY = "postgres:last_readonly"
READONLY_MODE_KEY = "readonly_mode"
PG_READONLY_MODE_KEY = "readonly_mode:postgres"
USER_READONLY_MODE_KEY = "readonly_mode:user"
PG_FORCE_READONLY_MODE_KEY = "readonly_mode:postgres_force"
STAFF_WRITES_ONLY_MODE_KEY = "readonly_mode:staff_writes_only"
READONLY_KEYS = [
    READONLY_MODE_KEY,
    PG_READONLY_MODE_KEY,
    USER_READONLY_MODE_KEY,
    PG_FORCE_READONLY_MODE_KEY,
  ]
end
