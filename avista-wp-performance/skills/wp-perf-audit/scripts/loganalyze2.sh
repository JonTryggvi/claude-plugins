#!/bin/bash
cd ~/site/logs || exit 1
LOG=access.log

echo "==================== HOURLY request volume + slow(>10s) count ===================="
awk -F'"' '{
  match($1,/:[0-9]{2}:/); hr=substr($1,RSTART+1,2)
  # extract hour from [02/Jul/2026:HH:MM:SS
  h=substr($1,index($1,":")-2,2)  # fallback
  t=$9; gsub(/[^0-9.]/,"",t); rt=t+0
  split($1,a," "); ts=a[4]  # [02/Jul/2026:HH:MM:SS
  hour=substr(ts,14,2)
  cnt[hour]++; if(rt>10) slow[hour]++
} END{ for(h=0;h<24;h++){k=sprintf("%02d",h); if(cnt[k]) printf "  %s:00  %5d req   %4d slow(>10s)\n",k,cnt[k],slow[k]+0} }' "$LOG"

echo ""
echo "==================== PROFILES of the 4 most expensive IPs ===================="
for ip in 152.163.2.216 157.157.48.169 87.121.23.125 194.144.63.54; do
  echo "----- $ip -----"
  echo -n "  UA: "; grep -m1 "^$ip " "$LOG" | awk -F'"' '{print $6}' | cut -c1-120
  echo -n "  status codes: "; grep "^$ip " "$LOG" | awk -F'"' '{split($3,b," ");print b[1]}' | sort | uniq -c | sort -rn | tr '\n' ' '
  echo ""
  echo "  sample paths:"; grep "^$ip " "$LOG" | awk -F'"' '{split($2,r," ");print r[2]}' | sort | uniq -c | sort -rn | head -4 | cut -c1-110
done

echo ""
echo "==================== 499s (client gave up waiting) by UA ===================="
awk -F'"' '{split($3,b," "); if(b[1]==499) print $6}' "$LOG" | sort | uniq -c | sort -rn | head -8 | cut -c1-120

echo ""
echo "==================== PHP SLOW LOG ===================="
echo -n "slow events logged: "; grep -c "script_filename" php_slow.log 2>/dev/null
echo "  time window:"; grep -oE '^\[[0-9]{2}-[A-Za-z]+-[0-9]{4} [0-9:]+' php_slow.log 2>/dev/null | head -1; grep -oE '^\[[0-9]{2}-[A-Za-z]+-[0-9]{4} [0-9:]+' php_slow.log 2>/dev/null | tail -1
echo "  most common top-of-stack function (what it was stuck in):"
grep -oE '[a-zA-Z_]+\(\) ' php_slow.log 2>/dev/null | sort | uniq -c | sort -rn | head -12

echo ""
echo "==================== WAF LOG ===================="
echo -n "waf lines: "; wc -l < waf.log 2>/dev/null
echo "  sample recent entries:"; tail -5 waf.log 2>/dev/null | cut -c1-160
