# Offhand Items
This is a port of [mcl_offhand](https://github.com/MineClone2/MineClone2/tree/master/mods/HUD/mcl_offhand) for use with any other Minetest subgame.
Instead of using the offhand as a shield slot, this mod lets you use it for any item of your choice.
You can switch items between hands by pressing a configurable button (by default aux1 or E). When using a tool, press right-click to use the action of your offhand.
This lets you place torches and other nodes without having to put away your sword or pickaxe.

## Compatibility Notes

### Recommended Mods
This mod should work with any game and configuration. However, the following mods are recommended to make the most out of it:

* [visible_wielditem](https://content.minetest.net/packages/LMD/visible_wielditem/) - Attaches a 3D preview of the held item in your main hand. Recommended for visual consistency. Disable the *wieldview* mod if you also use 3d_armors.
* [wielded_light](https://content.minetest.net/packages/bell07/wielded_light/) - Registers held items as light sources. Also works for items in your offhand. You might also be interested in the [3d_armor_light](https://content.minetest.net/packages/AntumDeluge/3d_armor_light/) extension.

### Mineclone
Mineclone subgames are not supported as this offhand is likely to conflict with their own implementations.

### Bones (redo)
For use with the "bones (redo)" mod, go into that mod's settings and add "offhand" to the list of handled inventories:
```
bones.lists_to_bones = main,craft,armor,offhand
```
The normal bones mod will work out-of-the-box.

## Credit & License
This mod is licensed under GNU GPL v3 like the original.
Check [Mineclone 2's Credit section](https://github.com/MineClone2/MineClone2/blob/master/CREDITS.md) for information on the original authors.

All content in the `wielditem.lua` is copied from [visible_wielditem](https://content.minetest.net/packages/LMD/visible_wielditem/) by appgurueu (aka LMD). Files in that specific folder are dual-licensed under GNU GPL v3 as well as MIT.