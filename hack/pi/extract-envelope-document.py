#!/usr/bin/env python3
"""Extract envelope document field from sealhub-data YAML (stdout)."""
import sys
import yaml

def main() -> None:
    data = yaml.safe_load(sys.stdin.read())
    if not isinstance(data, dict) or "document" not in data:
        # plain hub API JSON
        if "Document" in data:
            sys.stdout.write(data["Document"])
            return
        sys.exit("no document field")
    doc = data["document"]
    if isinstance(doc, str):
        sys.stdout.write(doc)
    else:
        sys.stdout.write(yaml.dump(doc))

if __name__ == "__main__":
    main()
