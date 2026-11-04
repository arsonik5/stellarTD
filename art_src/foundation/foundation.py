"""Foundation (scenes/foundation.tscn) - 2.0 x 0.25 x 2.0 floor tile, origin at its CENTRE (as the scene's box).
Tiles edge to edge: every outer face sits exactly on +/-1.0 and +/-0.125, nothing protrudes. Kept cheap (many per base).
Four perimeter beams welded at the corners carry a deck plate with recessed seams and anti-slip tread."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *

kit.begin(kit.out_dir())
foundation_block(0.25)
kit.finish("SM_Foundation")
