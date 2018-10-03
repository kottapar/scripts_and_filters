#!/bin/bash
#set -x

###############################################################################
# Purpose     : Gather Performance and error logs every three minutes and send them
#               over to the Unix central syslog/logstash server
#
######### CHANGE LOG #########
# 08-10-2017-updating to copy script to the Linux Prod servers
# 15-10-2017--adding check for rsyslog file and restarting rsyslog on RHEL6,7
# 22-10-2017--fixed to calculate used memory using 'active memory' from vmstat; also vmstat changed to vmstat 1 4
#                     to prevent reading the first summary line
# 23-10-2017--adding server-specific thresholds feature
# 07-01-2018--change to fetch ip address where `hostname` is added to loopback in /etc/hosts
#
#
#
#
#
###############################################################################


## get ip address
ip_addr=$(ping -qc1 `hostname`|head -1|awk '{print $3}'|sed 's/[():]//g')
if [[ $ip_addr == "127.0.0.1" ]]; then
  ip_addr=$(grep `hostname` /etc/hosts|egrep -v '127.0.0.1|#'|awk '{print $1}')
  if [[ -z $ip_addr ]]; then    
    ip_addr="0.0.0.0" 
  fi
fi

hname=`hostname | awk -F'.' '{print $1}'|tr 'A-Z' 'a-z'`

## check if a new rsyslog file is copied to the RHEL6 and RHEL7 servers. If yes, then copy it
## over to /etc/rsyslog.d/ and restart rsyslog

#declaring syslog file
rsfile=/infra/scripts/10-lnx_error.conf-PROD
dtnow=$(date +%s)
dtfile=$(date -r $rsfile +%s)
fileday=$(date -r $rsfile +%d)
daynow=$(date +%d)

#print just the OS number like 5 or 6 or 7
os=`awk -F. '{print $1}' /etc/redhat-release | awk '{print $NF}'`

if [[ ( $os -eq 6 ) || ( $os -eq 7 ) ]]; then
  if [[ ( -s $rsfile ) && ( $fileday -eq $daynow ) ]]; then
# get the time difference in min between now and file's timestamp
    dff=$(echo $(( ($dtnow - $dtfile) / 60 )))
    if [[ $dff -lt 6 ]]; then
      /bin/cp $rsfile /etc/rsyslog.d/10-lnx_error.conf
# We couldn't find any way to get the hostname in the template via rsyslog; hence the below hack	  
      sed -i 's/LNX_E/'"$hname LNX_E"'/g' /etc/rsyslog.d/10-lnx_error.conf
      /sbin/service rsyslog restart
    fi
  fi
fi

## temp dir to store logs
tmp_dir=/tmp/ptmpd

## log to gather vmstat output
vmlog=$tmp_dir/vmstat.out
sarlog=$tmp_dir/sar.out

## log which the logger will use to log to syslog
perflog=$tmp_dir/perf.out
errlog=$tmp_dir/err.out

mkdir -p $tmp_dir
> $perflog

## gather the vmstats
vmstat 1 4 > $vmlog

## Common Thresholds
MEMTHRESH=80
SWAPTHRESH=35
CPUTHRESH=90
WIOTHRESH=$(grep -c ^processor /proc/cpuinfo)
RQTHRESH=$WIOTHRESH
await_thr=20
busy_thre=75


#### SERVER-SPECIFIC THRESHOLDS ####
# Create thresholds for specific servers. For eg: if we're aware that a server is cpu-intensive add a higher threshold
# here
#hlist=(server1 server2)
#for hst in $(echo ${hlist[@]}); do
#  if [[ $(echo $hname | grep $hst) ]]; then
#    MEMTHRESH=100
#    SWAPTHRESH=50
#    CPUTHRESH=95
#    WIOTHRESH=$(grep -c ^processor /proc/cpuinfo)
#    RQTHRESH=$WIOTHRESH
#    await_thr=40
#    busy_thre=90
#  fi
#done

## Gather errors in the last 3 min and log to syslog
timestamp=$(perl -MPOSIX -le 'print strftime "%m%d%H%M%y",localtime(time()-180)')

for cnt in 1 2 3 4; do
  for par in memp swapp cpup iowp rqp; do
    if [[ -f  $tmp_dir/$par$cnt ]]; then
      if [[ ! -s $tmp_dir/$par$cnt ]]; then
        echo "0" > $tmp_dir/$par$cnt
      fi
    else
      touch $tmp_dir/$par$cnt
      if [[ ! -s $tmp_dir/$par$cnt ]]; then
        echo "0" > $tmp_dir/$par$cnt
      fi
    fi
  done
done

### MEMORY: calculate the percentage of used memory
#memc=$(/usr/bin/free -m|grep Mem|awk '{print $3 / $2 * 100}' | awk -F. '{print $1}')
#memc=$(vmstat -s -S K|head -3|xargs|awk '{print $9 / $1 * 100}' | awk -F. '{print $1}') 
memc=$(egrep '^MemTotal|^MemFree|^Cached' /proc/meminfo|xargs|awk 'OFMT="%0.0f" {print ($2 - ($5 + $8)) / $2 * 100}')
memp1=$(cat $tmp_dir/memp1)
memp2=$(cat $tmp_dir/memp2)
memp3=$(cat $tmp_dir/memp3)
memp4=$(cat $tmp_dir/memp4)
if [[ ( $memc -gt $MEMTHRESH ) && ( $memp1 -gt $MEMTHRESH ) && ( $memp2 -gt $MEMTHRESH ) ]]; then
  echo "$hname $ip_addr memory $memp4,$memp3,$memp2,$memp1,$memc" >> $perflog
fi
cat $tmp_dir/memp3 > $tmp_dir/memp4
cat $tmp_dir/memp2 > $tmp_dir/memp3
cat $tmp_dir/memp1 > $tmp_dir/memp2
echo $memc > $tmp_dir/memp1

### SWAP:
swapc=$(/usr/bin/free -m|grep Swap|awk '{print $3 / $2 * 100}' | awk -F. '{print $1}')
swapp1=$(cat $tmp_dir/swapp1)
swapp2=$(cat $tmp_dir/swapp2)
swapp3=$(cat $tmp_dir/swapp3)
swapp4=$(cat $tmp_dir/swapp4)
if [[ ( $swapc -gt $SWAPTHRESH ) && ( $swapp1 -gt $SWAPTHRESH ) && ( $swapp2 -gt $SWAPTHRESH ) ]]; then
  echo "$hname $ip_addr swap $swapp4,$swapp3,$swapp2,$swapp1,$swapc" >> $perflog
fi
cat $tmp_dir/swapp3 > $tmp_dir/swapp4
cat $tmp_dir/swapp2 > $tmp_dir/swapp3
cat $tmp_dir/swapp1 > $tmp_dir/swapp2
echo $swapc > $tmp_dir/swapp1

### CPU:
cpuc=$(tail -n3 $vmlog | awk '{print 100 - $15}' | awk '{ sum+=$1} END {print sum/3}' | awk -F. '{print $1}')
cpup1=$(cat $tmp_dir/cpup1)
cpup2=$(cat $tmp_dir/cpup2)
cpup3=$(cat $tmp_dir/cpup3)
cpup4=$(cat $tmp_dir/cpup4)
if [[ ( $cpuc -gt $CPUTHRESH ) && ( $cpup1 -gt $CPUTHRESH ) && ( $cpup2 -gt $CPUTHRESH ) ]]; then
  echo "$hname $ip_addr cpu $cpup4,$cpup3,$cpup2,$cpup1,$cpuc" >> $perflog
fi
cat $tmp_dir/cpup3 > $tmp_dir/cpup4
cat $tmp_dir/cpup2 > $tmp_dir/cpup3
cat $tmp_dir/cpup1 > $tmp_dir/cpup2
echo $cpuc > $tmp_dir/cpup1

### CPU WAIT IO:
iowc=$(cat $vmlog | tail -n3 | awk '{ sum+=$16} END {print sum/3}' | awk -F. '{print $1}')
iowp1=$(cat $tmp_dir/iowp1)
iowp2=$(cat $tmp_dir/iowp2)
iowp3=$(cat $tmp_dir/iowp3)
iowp4=$(cat $tmp_dir/iowp4)
if [[ ( $iowc -gt $WIOTHRESH ) && ( $iowp1 -gt $WIOTHRESH ) && ( $iowp2 -gt $WIOTHRESH ) ]]; then
  echo "$hname $ip_addr iowait $iowp4,$iowp3,$iowp2,$iowp1,$iowc" >> $perflog
fi
cat $tmp_dir/iowp3 > $tmp_dir/iowp4
cat $tmp_dir/iowp2 > $tmp_dir/iowp3
cat $tmp_dir/iowp1 > $tmp_dir/iowp2
echo $iowc > $tmp_dir/iowp1

### RUN QUEUE:
rqc=$(cat $vmlog | tail -n3 | awk '{ sum+=$1} END {print sum/3}' | awk -F. '{print $1}')
rqp1=$(cat $tmp_dir/rqp1)
rqp2=$(cat $tmp_dir/rqp2)
rqp3=$(cat $tmp_dir/rqp3)
rqp4=$(cat $tmp_dir/rqp4)
if [[ ( $rqc -gt $RQTHRESH ) && ( $rqp1 -gt $RQTHRESH ) && ( $rqp2 -gt $RQTHRESH ) ]]; then
  echo "$hname $ip_addr runq $rqp4,$rqp3,$rqp2,$rqp1,$rqc" >> $perflog
fi
cat $tmp_dir/rqp3 > $tmp_dir/rqp4
cat $tmp_dir/rqp2 > $tmp_dir/rqp3
cat $tmp_dir/rqp1 > $tmp_dir/rqp2
echo $rqc > $tmp_dir/rqp1

## Gather SAR stats
# prints device,await,%util to a file
sar -p -d 1 1|grep Average|grep -v DEV|awk '{print $2,$8,$10}' > $sarlog

for cnt in 1 2 3 4; do
  for par in dsk_await_p dsk_busy_p; do
    if [[ -f  $tmp_dir/$par$cnt ]]; then
      if [[ ! -s $tmp_dir/$par$cnt ]]; then
        for disk in $(awk '{print $1}' $sarlog); do
          echo "$disk 0" >> $tmp_dir/$par$cnt
        done
      fi
    else
      touch $tmp_dir/$par$cnt
      if [[ ! -s $tmp_dir/$par$cnt ]]; then
        for disk in $(awk '{print $1}' $sarlog); do
          echo "$disk 0" >> $tmp_dir/$par$cnt
        done
      fi
    fi
  done
done

### DISK AVERAGE WAIT
> $tmp_dir/dsk_await_p1tmp

for disk in $(awk '{print $1}' $sarlog); do
  cdsk_await=$(grep -w $disk $sarlog | awk '{print $2}'|awk -F. '{print $1}')
  cdsk_await_p1=$(grep -w $disk $tmp_dir/dsk_await_p1 | awk '{print $2}'|awk -F. '{print $1}')
  cdsk_await_p2=$(grep -w $disk $tmp_dir/dsk_await_p2 | awk '{print $2}'|awk -F. '{print $1}')
  cdsk_await_p3=$(grep -w $disk $tmp_dir/dsk_await_p3 | awk '{print $2}'|awk -F. '{print $1}')
  cdsk_await_p4=$(grep -w $disk $tmp_dir/dsk_await_p4 | awk '{print $2}'|awk -F. '{print $1}')
  if [[ ( $cdsk_await -gt $await_thr ) && ( $cdsk_await_p1 -gt $await_thr ) && ( $cdsk_await_p2 -gt $await_thr ) ]]; then
    echo "$hname $ip_addr disk_await $disk $cdsk_await_p4,$cdsk_await_p3,$cdsk_await_p2,$cdsk_await_p1,$cdsk_await" >> $perflog
  fi
  echo "$disk $cdsk_await" >> $tmp_dir/dsk_await_p1tmp
done
cat $tmp_dir/dsk_await_p3 > $tmp_dir/dsk_await_p4
cat $tmp_dir/dsk_await_p2 > $tmp_dir/dsk_await_p3
cat $tmp_dir/dsk_await_p1 > $tmp_dir/dsk_await_p2
cat $tmp_dir/dsk_await_p1tmp > $tmp_dir/dsk_await_p1

### DISK BUSY
> $tmp_dir/dsk_busy_p1tmp

for disk in $(awk '{print $1}' $sarlog); do
  cdsk_busy=$(grep -w $disk $sarlog | awk '{print $3}'|awk -F. '{print $1}')
  cdsk_busy_p1=$(grep -w $disk $tmp_dir/dsk_busy_p1 | awk '{print $3}'|awk -F. '{print $1}')
  cdsk_busy_p2=$(grep -w $disk $tmp_dir/dsk_busy_p2 | awk '{print $3}'|awk -F. '{print $1}')
  cdsk_busy_p3=$(grep -w $disk $tmp_dir/dsk_busy_p3 | awk '{print $3}'|awk -F. '{print $1}')
  cdsk_busy_p4=$(grep -w $disk $tmp_dir/dsk_busy_p4 | awk '{print $3}'|awk -F. '{print $1}')
  if [[ ( $cdsk_busy -gt $busy_thre ) && ( $cdsk_busy_p1 -gt $busy_thre ) && ( $cdsk_busy_p2 -gt $busy_thre ) ]]; then
    echo "$hname $ip_addr disk_busy $disk $cdsk_busy_p4,$cdsk_busy_p3,$cdsk_busy_p2,$cdsk_busy_p1,$cdsk_busy" >> $perflog
  fi
  echo "$disk $cdsk_busy" >> $tmp_dir/dsk_busy_p1tmp
done
cat $tmp_dir/dsk_busy_p3 > $tmp_dir/dsk_busy_p4
cat $tmp_dir/dsk_busy_p2 > $tmp_dir/dsk_busy_p3
cat $tmp_dir/dsk_busy_p1 > $tmp_dir/dsk_busy_p2
cat $tmp_dir/dsk_busy_p1tmp > $tmp_dir/dsk_busy_p1

### UPTIME
# log a server_rebooted message if the uptime contains min and if the no of min is less than 4
uptmin=$(/usr/bin/uptime | awk '{print $3}')
if [[ $(/usr/bin/uptime | awk '{print $4}' | grep min) ]]; then
  uptmin=$(/usr/bin/uptime | awk '{print $3}')
  if [[ $uptmin -le 4 ]]; then
    uptsec=$(expr $uptmin \* 60)
    timestamp=$(perl -MPOSIX -le "print strftime '%b %d %H%M%S',localtime(time()-$uptsec)")
    /usr/bin/logger -p local5.info -t LNX_E "$hname $ip_addr $timestamp server_rebooted" 
  fi
fi


## log the file to syslog
## using info here as we connfigured rsyslog to log anything below 6(info) as error
/usr/bin/logger -p local5.info -t LNX_P -f $perflog
