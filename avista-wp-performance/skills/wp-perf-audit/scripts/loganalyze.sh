#!/bin/bash
cd ~/site/logs || exit 1
LOG=access.log

echo "==================== WINDOW ===================="
echo -n "first: "; head -1 "$LOG" | grep -oE '\[[0-9]{2}/[A-Za-z]+/[0-9]{4}:[0-9:]+'
echo -n "last:  "; tail -1 "$LOG" | grep -oE '\[[0-9]{2}/[A-Za-z]+/[0-9]{4}:[0-9:]+'
echo -n "total requests: "; wc -l < "$LOG"

echo ""
echo "==================== AGGREGATE (awk) ===================="
awk -F'"' '
{
  total++
  split($1,a," "); ip=a[1]
  split($3,b," "); status=b[1]
  t=$9; gsub(/[^0-9.]/,"",t); rt=t+0
  cache=$12
  req=$2; split(req,r," "); path=r[2]

  st[status]++
  cc[cache]++
  sum+=rt
  if(rt>max){max=rt; maxl=$0}
  if(rt>20)g20++; else if(rt>10)g10++; else if(rt>5)g5++; else if(rt>2)g2++

  # count path segments (depth) to flag looping/trap URLs
  d=gsub(/\//,"/",path)
  if(d>=8) deep++

  if(path ~ /xmlrpc\.php/) xmlrpc++
  if(path ~ /wp-login\.php/) login++
  if(path ~ /wp-cron\.php/) wpcron++
  if(path ~ /\/wp-json/) wpjson++
  if(path ~ /[?&]s=/) srch++

  lua=tolower($6)
  if(lua ~ /bot|spider|crawl|slurp|bytespider|claudebot|gptbot|ahrefs|semrush|facebookexternal|python-requests|curl|wget|scrapy|headless|bing|google|yandex|petal|amazonbot|dataforseo|meta-external/) bot++
}
END{
  printf "avg req_time=%.2fs  max=%.2fs\n", sum/total, max
  printf "slow buckets: >2s=%d  >5s=%d  >10s=%d  >20s=%d\n", g2,g5,g10,g20
  printf "bot-UA requests=%d (%.1f%%)  human-ish=%d\n", bot, bot*100.0/total, total-bot
  printf "deep/looping paths (>=8 segments)=%d\n", deep
  printf "suspicious: xmlrpc=%d wp-login=%d wp-cron=%d wp-json=%d search=%d\n", xmlrpc,login,wpcron,wpjson,srch
  print "--- status codes ---"; for(s in st) printf "  %s: %d\n", s, st[s]
  print "--- cache status ---"; for(c in cc) printf "  [%s]: %d\n", c, cc[c]
  print "--- SLOWEST request ---"; print maxl
}' "$LOG"

echo ""
echo "==================== TOP 20 IPs by request count ===================="
awk -F'"' '{split($1,a," ");print a[1]}' "$LOG" | sort | uniq -c | sort -rn | head -20

echo ""
echo "==================== TOP 20 IPs by TOTAL request-time (CPU cost) ===================="
awk -F'"' '{split($1,a," ");ip=a[1]; t=$9;gsub(/[^0-9.]/,"",t); s[ip]+=t; n[ip]++} END{for(i in s)printf "%8.1fs  %6d req  %s\n",s[i],n[i],i}' "$LOG" | sort -rn | head -20

echo ""
echo "==================== TOP 15 User-Agents ===================="
awk -F'"' '{print $6}' "$LOG" | sort | uniq -c | sort -rn | head -15 | cut -c1-160

echo ""
echo "==================== TOP 15 deepest/looping paths ===================="
awk -F'"' '{req=$2; split(req,r," "); path=r[2]; d=gsub(/\//,"/",path); if(d>=7) print path}' "$LOG" | sort | uniq -c | sort -rn | head -15 | cut -c1-140
