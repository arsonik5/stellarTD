import re

with open(r'C:\Users\Admin\Documents\stellar-td\scripts\player\player.gd', 'r') as f:
    lines = f.readlines()

func_lines = [i for i, line in enumerate(lines) if line.strip().startswith('func ')]

print(f"Total functions found: {len(func_lines)}")

funcs = []
for idx in func_lines:
    name = lines[idx].strip()
    funcs.append(name)

# Find function after _exit_ship
try:
    exit_idx = funcs.index('_exit_ship')
    if exit_idx + 1 < len(funcs):
        next_func = funcs[exit_idx + 1]
        print(f"Function after _exit_ship: {next_func}")
except ValueError:
    print("Exit ship not found")

# Last function
if funcs:
    print(f"Last function: {funcs[-1]}")

# Count pipe functions
pipe_funcs = [f for f in funcs if 'pipe' in f.lower()]
print(f"Pipe functions ({len(pipe_funcs)}):")
for f in pipe_funcs:
    print(f"  - {f}")
