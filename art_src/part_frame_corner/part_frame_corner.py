"""Part frame_corner (blockout) - see art_src/parts_lib.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import parts_lib
parts_lib.build("frame_corner")
