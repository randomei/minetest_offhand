
std = "luajit+minetest+offhand"
ignore = { "212" }

files[".luacheckrc"].std = "min+luacheck"

stds.luacheck = {}
stds.luacheck.globals = {
    "files",
    "ignore",
    "std",
    "stds"
}

stds.minetest = {}
stds.minetest.read_globals = {
    "DIR_DELIM",
    "minetest",
    "dump",
    "vector",
    "VoxelManip",
    "VoxelArea",
    "PseudoRandom",
    "PcgRandom",
    "ItemStack",
    "Settings",
    "unpack",
    "assert",
    "Raycast",
    table = { fields = { "copy", "indexof" } },
    math = { fields = { "sign" } }
}

stds.offhand = {}
stds.offhand.globals = {
    "minetest",
    "offhand"
}
stds.offhand.read_globals = {
    "bones",
    "controls",
    "wielded_light"
}