import re

with open(r'C:\Users\Admin\Documents\stellar-td\scripts\player\player.gd', 'r') as f:
    content = f.read()

# Match func definitions at start of line
matches = re.findall(r'^func\s+(\w+)', content, re.MULTILINE)
funcs = matches

print(f"Total functions: {len(funcs)}")
print()

for i, name in enumerate(funcs):
    print(f"{i+1:3}. {name}")

# Pipe functions
pipe_funcs = [f for f in funcs if 'pipe' in f.lower()]
print(f"\nPipe functions: {len(pipe_funcs)}")
for f in pipe_funcs:
    print(f"  - {f}")
