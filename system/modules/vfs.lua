-------------------------
--- Filesystem Module ---
-------------------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@alias fs_open_mode
---| '"r"'   # read
---| '"rb"'  # read (binary)
---| '"w"'   # write
---| '"wb"'  # write (binary)
---| '"a"'   # append
---| '"ab"'  # append (binary)

---@alias i_type
---| '"dir"'
---| '"file"'
---| '"symlink"'

---@class inode
---@field i_uid integer
---@field i_gid integer
---@field i_atime integer
---@field i_mtime integer
---@field i_ctime integer
---@field i_btime integer
---@field i_ino string
---@field i_size integer
---@field i_type i_type
---@field i_mode integer
---@field i_openmode fs_open_mode
---@field i_children inode[]       
---@field i_parent inode|nil       
---@field i_link string|nil    
---@field i_dentries dentry[]

---@class qstr
---@field name string  
---@field len integer  
---@field hash integer 

---@class dentry
---@field d_count integer
---@field d_lock boolean
---@field d_mounted boolean
---@field d_inode inode|nil
---@field d_parent dentry|nil
---@field d_name qstr
---@field d_child dentry[]      
---@field d_subdirs dentry[]    
---@field d_alias dentry[]      
---@field d_time number         
---@field d_op fs            
---@field d_sb any super block; currentry unused  
---@field d_child_map table<string, dentry>

---@class vfs : fs
local vfs = {}

---@return file
function vfs.open(path, mode)
    
end

--- Virtual Open - opens a file and returns a file descriptor.
--- @return integer # descriptor
function vfs.vopen(path, mode)
    
end

function vfs.vread(fd, size)
    
end

function vfs.vwrite(fd, data)
    
end

function vfs.vclose(fd)
    
end

function vfs.makeDirectory(path)
    
end

function vfs.mount(fs, mount) 
    
end

function vfs.umount(mount)
    
end

function vfs.attributes(path)
    
end

function vfs.list(path)
    
end

return vfs, "vfs"
