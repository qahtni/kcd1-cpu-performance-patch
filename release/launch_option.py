# CPU Performance Patch: Steam launch option for Kingdom Come: Deliverance (app 379430).
#   python3 -I launch_option.py add|remove|suggest|check LOCALCONFIG.vdf...
# add     puts WINEDLLOVERRIDES="version=n,b" in front of the launch options (merged into an
#         existing WINEDLLOVERRIDES), so Proton loads version.dll from the game folder.
# remove  takes exactly that entry out again.
# suggest only prints what the launch options would become (read-only).
# check   read-only: exit 0 = set for every file, 3 = set for none, 1 = some.
# Steam must be closed for add/remove: it rewrites localconfig.vdf when it exits.
# Only the one LaunchOptions value changes; the rest of the file stays byte for byte.
# Backup: localconfig.vdf.kcdperf-backup. Exit 0 = done for every file, 1 = not.
import os, re, shutil, sys

APP = "379430"
ENTRY = "version=n,b"
PATH = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"]
WDO = re.compile(r'(^|\s)WINEDLLOVERRIDES=(?:"([^"]*)"|\'([^\']*)\'|([^\s"\']*))')


def unesc(raw):
    out, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c == "\\" and i + 1 < len(raw):
            n = raw[i + 1]
            out.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"'}.get(n, c + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def tokens(s):
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c in " \t\r\n\ufeff":
            i += 1
        elif s.startswith("//", i):
            j = s.find("\n", i)
            i = n if j < 0 else j
        elif c in "{}":
            yield c, None, i, i + 1
            i += 1
        elif c == '"':
            j = i + 1
            while j < n and s[j] != '"':
                j += 2 if s[j] == "\\" else 1
            if j >= n:
                raise ValueError("unterminated text at byte %d" % i)
            yield "s", unesc(s[i + 1:j]), i, j + 1
            i = j + 1
        else:
            raise ValueError("unexpected text at byte %d" % i)


class Node:
    def __init__(self, key, kpos):
        self.key, self.kpos = key, kpos
        self.value = None      # text value, or list of child Nodes for a block
        self.vpos = None       # (start, end) of the quoted value, or of the { } block


def parse(s):
    toks = list(tokens(s))
    pos = 0

    def items(inner):
        nonlocal pos
        out = []
        while True:
            if pos >= len(toks):
                if inner:
                    raise ValueError("missing }")
                return out, None
            kind, val, a, b = toks[pos]
            if kind == "}":
                if not inner:
                    raise ValueError("extra } at byte %d" % a)
                pos += 1
                return out, a
            if kind != "s" or pos + 1 >= len(toks):
                raise ValueError("bad layout at byte %d" % a)
            node = Node(val, a)
            pos += 1
            kind2, val2, a2, b2 = toks[pos]
            if kind2 == "s":
                node.value, node.vpos = val2, (a2, b2)
                pos += 1
            elif kind2 == "{":
                pos += 1
                node.value, close = items(True)
                node.vpos = (a2, close + 1)
            else:
                raise ValueError("bad layout at byte %d" % a2)
            out.append(node)

    return items(False)[0]


def child(nodes, key):
    for n in nodes:
        if isinstance(n.value, list) and n.key.lower() == key.lower():
            return n
    return None


def find_opts(s):
    """-> (apps block node or None, app block node or None, LaunchOptions node or None)"""
    nodes, node = parse(s), None
    for k in PATH:
        node = child(nodes, k)
        if node is None:
            return None, None, None
        nodes = node.value
    app = child(nodes, APP)
    if app is None:
        return node, None, None
    for n in app.value:
        if not isinstance(n.value, list) and n.key.lower() == "launchoptions":
            return node, app, n
    return node, app, None


def wdo_match(v):
    m = None
    for m2 in WDO.finditer(v):
        m = m2
        break
    if m is None:
        return None
    cmd = v.find("%command%")
    if cmd >= 0 and m.start() > cmd:
        return None            # after %command% it is a game argument, not a variable
    return m


def entries_of(m):
    val = next(g for g in (m.group(2), m.group(3), m.group(4)) if g is not None)
    return [e for e in val.split(";") if e.strip()]


def version_entry(entries):
    for e in entries:
        dlls = e.split("=", 1)[0]
        if "version" in [d.strip().lower() for d in dlls.split(",")]:
            return e.strip()
    return None


def add_value(v):
    """-> (new value, state) state: added / already / other"""
    m = wdo_match(v)
    if m:
        ent = entries_of(m)
        cur = version_entry(ent)
        if cur is not None:
            return v, ("already" if cur.replace(" ", "") in ("version=n,b", "version=native,builtin", "version=n", "version=native") else "other")
        new = m.group(1) + 'WINEDLLOVERRIDES="' + ";".join(ent + [ENTRY]) + '"'
        return v[:m.start()] + new + v[m.end():], "added"
    pre = 'WINEDLLOVERRIDES="%s" ' % ENTRY
    if "%command%" in v:
        return pre + v.lstrip(), "added"
    rest = v.strip()
    return pre + "%command%" + (" " + rest if rest else ""), "added"


def remove_value(v):
    m = wdo_match(v)
    if not m:
        return v
    ent = entries_of(m)
    keep = [e for e in ent if e.strip() != ENTRY]
    if len(keep) == len(ent):
        return v
    if keep:
        new = v[:m.start()] + m.group(1) + 'WINEDLLOVERRIDES="' + ";".join(keep) + '"' + v[m.end():]
    else:
        tail = v[m.end():]
        new = v[:m.start()] + m.group(1) + tail.lstrip()
        if not v[:m.start()]:
            new = new.lstrip()
    s = new.strip()
    if s == "%command%":
        return ""
    if s.startswith("%command% ") and not new[:new.find("%command%")].strip():
        return s[len("%command% "):].lstrip()
    return new


def line_bounds(s, a):
    ls = s.rfind("\n", 0, a) + 1
    le = s.find("\n", a)
    return ls, (len(s) if le < 0 else le + 1)


def edit(path, mode):
    s = open(path, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in s else "\n"
    apps, app, lo = find_opts(s)
    if apps is None:
        return False, "no Steam app settings in this file, left alone"
    old = lo.value if lo else ""
    if mode == "remove":
        new = remove_value(old)
        if lo is None or new == old:
            return True, "not set"
        if new == "":
            ls, le = line_bounds(s, lo.kpos)
            if s[ls:lo.kpos].strip() == "" and s[lo.vpos[1]:le].strip() == "":
                out = s[:ls] + s[le:]
            else:
                out = s[:lo.vpos[0]] + '""' + s[lo.vpos[1]:]
        else:
            out = s[:lo.vpos[0]] + '"' + esc(new) + '"' + s[lo.vpos[1]:]
        state = "removed"
    else:
        new, state = add_value(old)
        if mode == "suggest":
            return True, new if state != "other" else "(already has a different version.dll setting: %s)" % old
        if state == "already":
            return True, "already set"
        if state == "other":
            return False, "the launch options already give version.dll a different setting, left alone: " + old
        if lo is not None:
            out = s[:lo.vpos[0]] + '"' + esc(new) + '"' + s[lo.vpos[1]:]
        elif app is not None:
            close = app.vpos[1] - 1
            ls, _ = line_bounds(s, close)
            ind = s[ls:close] if s[ls:close].strip() == "" else ""
            out = s[:ls] + ind + '\t"LaunchOptions"\t\t"' + esc(new) + '"' + nl + s[ls:]
        else:
            close = apps.vpos[1] - 1
            ls, _ = line_bounds(s, close)
            ind = s[ls:close] if s[ls:close].strip() == "" else ""
            out = (s[:ls] + ind + '\t"' + APP + '"' + nl + ind + "\t{" + nl + ind + '\t\t"LaunchOptions"\t\t"'
                   + esc(new) + '"' + nl + ind + "\t}" + nl + s[ls:])
    # check the result before it replaces the file
    _, _, lo2 = find_opts(out)
    got = lo2.value if lo2 else ""
    if got != new:
        return False, "edit check failed, file left alone"
    shutil.copy2(path, path + ".kcdperf-backup")
    tmp = path + ".kcdperf-tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(out)
        f.flush()
        os.fsync(f.fileno())
    shutil.copymode(path, tmp)
    os.replace(tmp, path)
    return True, state


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "check":
        got = []
        for p in sys.argv[2:]:
            try:
                _, _, lo = find_opts(open(p, encoding="utf-8", newline="").read())
                got.append(lo is not None and add_value(lo.value)[1] == "already")
            except (OSError, ValueError, UnicodeDecodeError):
                got.append(False)
        return 0 if all(got) else (3 if not any(got) else 1)
    if len(sys.argv) < 3 or sys.argv[1] not in ("add", "remove", "suggest"):
        print("usage: launch_option.py add|remove|suggest localconfig.vdf...")
        return 2
    ok = True
    for p in sys.argv[2:]:
        try:
            good, msg = edit(p, sys.argv[1])
        except (OSError, ValueError, UnicodeDecodeError) as e:
            good, msg = False, "could not read or write it (%s), left alone" % e
        user = os.path.basename(os.path.dirname(os.path.dirname(os.path.abspath(p))))
        print(msg if sys.argv[1] == "suggest" else "  Steam user %s: %s" % (user, msg))
        ok = ok and good
        if sys.argv[1] == "suggest":
            break
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
