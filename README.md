# funny platformer

idk what i'm doing here

needs [this](https://github.com/nesbox/TIC-80/pull/2453) branch for it to run or else it will say "THIS FUNCTION IS _NOT_ REAL!"

u should also build the pro version if u want to save ur changes without saving it as a production cart

### map editing

use LDtk for map editing, map is in converter/map.ldtk

to save map changes, REBUILD and run this in tic80:
```
import binary zig-out/bin/converter.wasm
run
```

if the map isn't too big it will say "done :)" and then u can import cart.wasm like normal.
you HAVE to rebuild everytime bc it's using an `embedFile` in the converter.
if ur curious what the converter is doing, it's saving the tileset to the map and clobbering the 7th map bank to contain the entity list.
