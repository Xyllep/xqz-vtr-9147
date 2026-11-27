#!/usr/bin/env python3
"""Mutabor VPN (gates.mutabor-sec.ru): регистрация через temp-mail (mail.tm) + пробный доступ на 3 дня.

Зависимости: только stdlib (python 3.8+).
Использование: python3 mutabor.py   -> выводит email/пароль и статус активации триала.
"""
import urllib.request, urllib.parse, urllib.error, http.cookiejar, json, random, string, time, re, sys

BASE = "https://gates.mutabor-sec.ru"
MAIL_API = "https://api.mail.tm"
PREFERRED_GROUP = "ge"  # Германия; список групп: ge fr ee nl usa sw rusw lt ltu fl

def mreq(url, data=None, headers=None, method=None):
    h = {'Content-Type': 'application/json', 'Accept': 'application/json'}
    h.update(headers or {})
    r = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None,
                               headers=h, method=method)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(r, timeout=20) as resp:
                return resp.status, resp.read().decode()
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and attempt < 2:
                time.sleep(3); continue
            raise

def sreq(opener, url, data=None, headers=None):
    h = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    if data and isinstance(data, dict):
        h["Content-Type"] = "application/x-www-form-urlencoded"
    h.update(headers or {})
    body = urllib.parse.urlencode(data).encode() if isinstance(data, dict) else (data.encode() if isinstance(data, str) else data)
    r = urllib.request.Request(url, data=body, headers=h)
    with opener.open(r, timeout=30) as resp:
        return resp.status, resp.geturl(), resp.read().decode(errors="replace")

def new_mailbox():
    st, doms = mreq(f"{MAIL_API}/domains")
    d = json.loads(doms)
    members = d["hydra:member"] if isinstance(d, dict) else d
    domain = members[0]["domain"]
    login = "".join(random.choices(string.ascii_lowercase, k=2) + random.choices(string.digits + string.ascii_lowercase, k=8))
    addr = f"{login}@{domain}"
    mpwd = "Mx" + "".join(random.choices(string.ascii_letters + string.digits, k=12)) + "!1"
    mreq(f"{MAIL_API}/accounts", {"address": addr, "password": mpwd})
    return addr, mpwd

def mail_token(addr, mpwd):
    st, body = mreq(f"{MAIL_API}/token", {"address": addr, "password": mpwd})
    return json.loads(body)["token"]

def poll_code(token, timeout=120):
    for _ in range(timeout // 4):
        st, body = mreq(f"{MAIL_API}/messages", headers={"Authorization": "Bearer " + token})
        items = json.loads(body)
        items = items["hydra:member"] if isinstance(items, dict) else items
        for m in items:
            st, full = mreq(f"{MAIL_API}/messages/{m['id']}", headers={"Authorization": "Bearer " + token})
            txt = json.loads(full).get("text") or ""
            mobj = re.search(r"\b(\d{6})\b", txt)
            if mobj:
                return mobj.group(1)
        time.sleep(4)
    return None

def main():
    cj = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

    addr, mpwd = new_mailbox()
    pwd = "".join(random.choices(string.ascii_letters + string.digits, k=14)) + "!Aa1"
    print(f"[mail] {addr}")

    st, url, html = sreq(op, f"{BASE}/auth/register", {"email": addr, "password": pwd})
    if "code_sent" not in url:
        print("register failed:", url); sys.exit(1)
    print("[register] код отправлен")

    tok = mail_token(addr, mpwd)
    code = poll_code(tok)
    if not code:
        print("код не пришёл"); sys.exit(1)
    print(f"[code] {code}")

    st, url, html = sreq(op, f"{BASE}/auth/verify", {"code": code})
    if not url.endswith("/lk"):
        print("verify failed:", url); sys.exit(1)
    print("[verify] ок, в личном кабинете")

    st, url, body = sreq(op, f"{BASE}/api/account/trial", json.dumps({"server_group": PREFERRED_GROUP}),
                         headers={"Content-Type": "application/json", "Accept": "application/json", "Referer": f"{BASE}/lk"})
    print("[trial]", body[:200])

    # ссылка подписки VPN
    st, url, html = sreq(op, f"{BASE}/lk")
    m = re.search(r'id="subscriptionConfigField"[^>]*value="([^"]+)"', html)
    sub_url = m.group(1) if m else None
    print("[vpn-link]", sub_url)

    creds = {"email": addr, "mail_password": mpwd, "site_password": pwd, "verified": True, "subscription_url": sub_url}
    with open("mutabor_account.json", "w") as f:
        json.dump(creds, f, indent=2)
    print("[done] акк сохранён в mutabor_account.json:", json.dumps(creds, ensure_ascii=False))

if __name__ == "__main__":
    main()
