#!/usr/bin/env python3
"""FoxWay-only nftables guard. Render mode is side-effect free for CI/review."""
import json
import re
import subprocess
import sys

TABLE='foxway_guard'
MARK=0x4657

def rules(interface, existed=False):
    if not re.fullmatch(r'(fwvless0|fw[a-f0-9]{10})',interface):
        raise ValueError('Not a FoxWay interface')
    # No generic established/related exception: existing physical sockets must close too.
    return ('delete table inet '+TABLE+'\n' if existed else '')+f'''table inet {TABLE} {{
 chain output {{
  type filter hook output priority -200; policy drop;
  oifname "lo" accept
  oifname "{interface}" accept
  meta mark {MARK} accept
  udp sport 68 udp dport 67 accept
  udp sport 546 udp dport 547 ip6 daddr fe80::/10 accept
  icmpv6 type {{ nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert }} ip6 hoplimit 255 accept
 }}
}}
'''

def invoke(*args,input=None):
    return subprocess.run(['/usr/sbin/nft',*args],input=input,text=True,capture_output=True,check=False)

def main():
    action=sys.argv[1]
    payload=json.loads(sys.stdin.read(4097) or '{}')
    if action=='render': print(rules(payload['interface'],payload.get('existed',False)));return
    present=invoke('list','table','inet',TABLE)
    if action=='status':print(json.dumps({'armed':present.returncode==0}));return
    if action=='off':
        if present.returncode==0 and invoke('delete','table','inet',TABLE).returncode!=0:raise RuntimeError('Cannot remove own guard')
        return
    if action!='arm':raise ValueError('Unknown command')
    if invoke('-f','-',input=rules(payload['interface'],present.returncode==0)).returncode!=0:
        raise RuntimeError('Cannot arm guard; nftables and administrative authorization required')

if __name__=='__main__':
    try:main()
    except Exception:sys.stderr.write('FoxWay firewall operation failed\n');sys.exit(1)
