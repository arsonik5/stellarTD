import re

with open(r'C:\Users\Admin\Documents\stellar-td\scripts\player\player.gd', 'r') as f:
    content = f.read()

# Match func definitions at start of line (after optional whitespace)
pattern = r'^(\s*)func\s+(\w+)'
matches = re.findall(pattern, content, re.MULTILINE)

funcs = [m[1] for m in matches]
print(f"Total functions: {len(funcs)}")
print()

for i, name in enumerate(funcs):
    print(f"{i+1:3}. {name}")

# Check specifically for pipe functions
pipe_funcs = [f for f in funcs if 'pipe' in f.lower()]
print(f"\nPipe functions: {len(pipe_funcs)}")
for f in pipe_funcs:
    print(f"  - {f}")

# Find _exit_ship position and what comes after
try:
    exit_idx = funcs.index('_exit_ship')
    print(f"\n_exit_ship is at index {exit_idx}")
    if exit_idx + 1 < len(funcs):
        print(f"Next function: {funcs[exit_idx + 1]}")
except ValueError as e:
    print(f"_exit_ship not found: {e}")

print(f"\nLast function: {funcs[-1]}")
