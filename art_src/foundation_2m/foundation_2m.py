"""Foundation 2 m (scenes/foundation_2m.tscn) - 2.0 x 2.0 x 2.0 block, origin at its CENTRE, faces exactly on
+/-1.0. Corner posts, ring beams top and bottom, cladding set into the sides, deck on top."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *

kit.begin(kit.out_dir())
foundation_block(2.0)
kit.finish("SM_Foundation2m")
