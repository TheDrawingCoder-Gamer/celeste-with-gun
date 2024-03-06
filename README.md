# funny platformer

idk what i'm doing here

needs [this](https://github.com/nesbox/TIC-80/pull/2453) branch for it to run or else it will say "THIS FUNCTION IS _NOT_ REAL!"

u should also build the pro version if u want to save ur changes without saving it as a production cart

### workflow

not much is left to inside tic80 itself

map is an LDtk map, in assets/maps/map.ldtk

sprites are in aseprite files

doing zig build will compile it to zig-out/bin/res.wasmp

if u do any editing in tic80 that isn't already overwritten by external stuff, do `zig build unpack_data`  
