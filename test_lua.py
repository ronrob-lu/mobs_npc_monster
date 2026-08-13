import re
with open('init.lua', 'r') as f:
    code = f.read()
print("on_step in init.lua:", "on_step" in code)
