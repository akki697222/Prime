---@type oc_env
_ENV = _ENV

--- GLOBAL
GLOBAL_DETAILED_PANIC_STACK_TRACE = true
GLOBAL_OS_NAME = "Prime OS (OpenComputers)"

--- init
INIT_EXEC = "/usr/sbin/init.lua"
INIT_PID = 1

--- OS
OS_TIME_ZONE_FILE = "/etc/timezone"
OS_DEFAULT_TIME_ZONE_OFFSET = 9

--- Filesystem
FS_READ_CHUNK_SIZE = 1024
FS_INODE_FILE = "/system/data/fs_inode.lua"
FS_INODE_LOOKUP_FILE = "/system/data/fs_inode_lookup.lua"
FS_MOUNT_PATH = "/mount/"
FS_SAVE_LOOKUP_TABLE = true