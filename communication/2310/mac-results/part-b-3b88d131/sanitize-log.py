"""Copy a log with device-flow codes and any token-like strings redacted."""
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8', errors='replace').read()
text = re.sub(r'(enter code )[A-Z0-9]{4}-[A-Z0-9]{4}', r'\1REDACTED', text)
text = re.sub(r'(code=)[A-Za-z0-9\-]+', r'\1REDACTED', text)
open(dst, 'w', encoding='utf-8').write(text)
