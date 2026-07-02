#!/bin/bash
cd ~/site/logs || exit 1
echo "=== server time now ==="; date
echo "=== firewall/robots deploy mtime ==="; ls -l --time-style=+%H:%M ~/site/public_html/robots.txt 2>/dev/null | awk '{print $6}'

awk -F'"' '
{
  split($1,a," "); ts=a[4]
  hh=substr(ts,14,2)+0; mm=substr(ts,17,2)+0; hhmm=hh*100+mm
  split($3,b," "); status=b[1]
  t=$9; gsub(/[^0-9.]/,"",t); rt=t+0
  if (hhmm>=1141) {
    tot++
    if (status==403){ f++; ft+=rt }
    else { okn++; okt+=rt }
  }
}
END{
  printf "\n=== requests since 11:41 (deploy) ===\n"
  printf "total: %d\n", tot
  printf "403 blocks: %d   avg time %.3fs\n", f, (f?ft/f:0)
  printf "non-403:    %d   avg time %.2fs\n", okn, (okn?okt/okn:0)
}' access.log

echo ""
echo "=== top user-agents getting 403 since 11:41 ==="
awk -F'"' '{split($1,a," ");ts=a[4];hh=substr(ts,14,2)+0;mm=substr(ts,17,2)+0;hhmm=hh*100+mm;split($3,b," ");if(hhmm>=1141 && b[1]==403)print $6}' access.log | sort | uniq -c | sort -rn | head -10 | cut -c1-90

echo ""
echo "=== sanity: 403s to blocked UAs should be FAST; MISS renders slow. Compare a blocked vs allowed sample ==="
awk -F'"' '{split($1,a," ");ts=a[4];hh=substr(ts,14,2)+0;mm=substr(ts,17,2)+0;hhmm=hh*100+mm;split($3,b," ");t=$9;gsub(/[^0-9.]/,"",t); if(hhmm>=1141 && b[1]==403 && t>2) print "SLOW-403(unexpected):",$6,t}' access.log | head -3
