import re

with open(r'C:\Users\Admin\Documents\stellar-td\scripts\player\player.gd', 'r') as f:
    lines = f.readlines()

# Find all func definitions (lines that START with 'func ')
func_lines = [i for i, line in enumerate(lines) if line.strip().startswith('func ')]

print(f"Total functions found: {len(func_lines)}")

for i, idx in enumerate(func_lines):
    print(f"{i+1}. Line {idx+1}: {lines[idx].strip()}")

# Find function after _exit_ship
for i, line in enumerate(lines):
    if 'func _exit_ship' in line:
        print(f"\n_exit_ship found at line {i+1}")
        if i + 1 < len(lines) and not lines[i+1].strip().startswith('#'):
            print(f"Next non-comment line: {lines[i+1].strip()}")

# Count pipe functions
pipe_funcs = [f for f in func_lines if 'pipe' in lines[f].lower()]
print(f"\nPipe function lines ({len(pipe_funcs)}):")
for idx in pipe_funcs:
    print(f"  Line {idx+1}: {lines[idx].strip()}")

# Last function
if func_lines:
    last_line = func_lines[-1]
    print(f"\nLast function at line {last_line+1}: {lines[last_line].strip()}")
