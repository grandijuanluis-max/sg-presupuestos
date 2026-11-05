with open("app.js", "r") as f:
    code = f.read()

# Find the block we added for canViewComprobante and remove it
import re

code = re.sub(
    r"if \(segPerms\.canViewComprobante\) \{\s*btns\.push\(`\s*<button class=\"btn btn-sm btn-primary\" onclick=\"event\.stopPropagation\(\); verDetallePedido\('\$\{p\.id\}', 'ver'\)\"[\s\S]*?`\);\s*\}",
    "",
    code
)

code = re.sub(
    r"<button class=\"btn btn-sm btn-primary\" onclick=\"event\.stopPropagation\(\); verDetallePedido\('\$\{p\.id\}'\)\"[\s\S]*?</i> Ver\s*</button>",
    "",
    code
)

with open("app.js", "w") as f:
    f.write(code)

