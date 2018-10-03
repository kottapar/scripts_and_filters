#!/usr/bin/bash
#set -x

###############################################################################
# Purpose     : Gather Performance and error logs every three minutes and send them
#		over to the Unix central syslog/logstash server
#
###############################################################################


## get ip address and hostname
ip_addr=$(ping -qc1 `hostname`|head -1|awk '{print $3}'|sed 's/[():]//g')
if [[ $ip_addr == "127.0.0.1" ]]; then
  ip_addr=$(grep `hostname` /etc/hosts|egrep -v '127.0.0.1|#'|awk '{print $1}')
  if [[ -z $ip_addr ]]; then
    ip_addr="0.0.0.0"
  fi
fi

hname=`hostname | awk -F'.' '{print $1}'|tr 'A-Z' 'a-z'`

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
vmstat 1 3 > $vmlog

## Common Thresholds
MEMTHRESH=85
SWAPTHRESH=35
CPUTHRESH=80
WIOTHRESH=$(cat $vmlog | sed -n '/lcpu/ s/.*lcpu=\([0-9.]*\) .*/\1/p')
RQTHRESH=$WIOTHRESH
dbthre=75
dsthre=20

#### SERVER-SPECIFIC THRESHOLDS ####
# Create thresholds for specific servers. For eg: if we're aware that a server is cpu-intensive add a higher threshold
# here. To create for a different set of servers just copy-paste the below para and change the servers and values
#
hlist=(server1 server2)
for hst in $(echo ${hlist[@]}); do
  if [[ $(echo $hname | grep $hst) ]]; then
    MEMTHRESH=105
    SWAPTHRESH=50
    CPUTHRESH=95
    WIOTHRESH=$(cat $vmlog | sed -n '/lcpu/ s/.*lcpu=\([0-9.]*\) .*/\1/p')
    RQTHRESH=$WIOTHRESH
    dbthre=95
    dsthre=30
  fi
done

############################################################

## Gather errpt in the last 3 min and log to syslog
# 03-10-2017 : filtering out unique records as duplicate errpt entries were flooding
# 04-10-2017 : changing uniq to sort -u as uniq is still giving duplicates

timestamp=$(perl -MPOSIX -le 'print strftime "%m%d%H%M%y",localtime(time()-180)')
## append ip address to the starting of the message
# 23-10-2017 : adding logic to prevent lunz related errors from being reported

lunzdsk=$(lsdev -Cc disk|grep LUNZ|awk '{print $1}'|xargs|tr ' ' '|')
errpt -s $timestamp | grep -v IDENTIFIER | sed 's/ \{1,\}/ /g;s/^/'"$hname $ip_addr"' /g' |egrep -v "$lunzdsk|D1E21BA3" | sort -u > $errlog

if [[ -s $errlog ]]; then
  /usr/bin/logger -p local5.alert -t AIX_E -f $errlog
fi

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

### MEMORY:
memc=$(svmon -G | grep memory | awk '{print $6 / $2 * 100}' | awk -F. '{print $1}')
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
swapc=$(lsps -s | tail -n1 | awk '{print $2}' | sed 's/%//g')
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
cpuc=$(cat $vmlog | tail -n3 | awk '{print 100 - $16}' | awk '{ sum+=$1} END {print sum/3}' | awk -F. '{print $1}')
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
iowc=$(cat $vmlog | tail -n3 | awk '{ sum+=$17} END {print sum/3}' | awk -F. '{print $1}')
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
sar -d 1 1 | grep .|sed '1,3d' > $sarlog

for cnt in 1 2 3 4; do
  for par in saropb_p sarops_p; do
    if [[ -f  $tmp_dir/$par$cnt ]]; then
      if [[ ! -s $tmp_dir/$par$cnt ]]; then
        for disk in $(lsdev -Cc disk | grep Available | grep -v LUNZ | egrep "PowerPath|SCSI|SAS|MPIO" | awk '{print $1}'); do
          echo "$disk 0" >> $tmp_dir/$par$cnt
        done
      fi
    else
      touch $tmp_dir/$par$cnt
      if [[ ! -s $tmp_dir/$par$cnt ]]; then
        for disk in $(lsdev -Cc disk | grep Available | grep -v LUNZ | egrep "PowerPath|SCSI|SAS|MPIO" | awk '{print $1}'); do
          echo "$disk 0" >> $tmp_dir/$par$cnt
        done
      fi
    fi
  done
done

### DISK BUSY
> $tmp_dir/saropb_p1tmp
# print only disk name and %busy to a file
awk '{print $(NF-6),$(NF-5)}' $sarlog > $tmp_dir/sar_busy
for disk in $(lsdev -Cc disk | grep Available | grep -v LUNZ | egrep "PowerPath|SCSI|SAS|MPIO" | awk '{print $1}'); do
  cdbusy=$(grep -w $disk $tmp_dir/sar_busy | awk '{print $2}')
  cdbusy_p1=$(grep -w $disk $tmp_dir/saropb_p1 | awk '{print $2}')
  cdbusy_p2=$(grep -w $disk $tmp_dir/saropb_p2 | awk '{print $2}')
  cdbusy_p3=$(grep -w $disk $tmp_dir/saropb_p3 | awk '{print $2}')
  cdbusy_p4=$(grep -w $disk $tmp_dir/saropb_p4 | awk '{print $2}')
  if [[ ( $cdbusy -gt $dbthre ) && ( $cdbusy_p1 -gt $dbthre ) && ( $cdbusy_p2 -gt $dbthre ) ]]; then
    echo "$hname $ip_addr disk_busy $disk $cdbusy_p4,$cdbusy_p3,$cdbusy_p2,$cdbusy_p1,$cdbusy" >> $perflog
  fi
  echo "$disk $cdbusy" >> $tmp_dir/saropb_p1tmp
done
/usr/bin/cp -f $tmp_dir/saropb_p3 $tmp_dir/saropb_p4
/usr/bin/cp -f $tmp_dir/saropb_p2 $tmp_dir/saropb_p3
/usr/bin/cp -f $tmp_dir/saropb_p1 $tmp_dir/saropb_p2
/usr/bin/cp -f $tmp_dir/saropb_p1tmp $tmp_dir/saropb_p1

### DISK SERVICE
> $tmp_dir/sarops_p1tmp
awk '{print $(NF-6),$(NF)+$(NF-1)}' $sarlog > $tmp_dir/sar_svc
for disk in $(lsdev -Cc disk | grep Available | grep -v LUNZ | egrep "PowerPath|SCSI|SAS|MPIO" | awk '{print $1}'); do
  cdavs=$(grep -w $disk $tmp_dir/sar_svc | awk '{print $2}' | awk -F. '{print $1}')
  cdavs_p1=$(grep -w $disk $tmp_dir/sarops_p1 | awk '{print $2}')
  cdavs_p2=$(grep -w $disk $tmp_dir/sarops_p2 | awk '{print $2}')
  cdavs_p3=$(grep -w $disk $tmp_dir/sarops_p3 | awk '{print $2}')
  cdavs_p4=$(grep -w $disk $tmp_dir/sarops_p4 | awk '{print $2}')
  if [[ ( $cdavs -gt $dsthre ) && ( $cdavs_p1 -gt $dsthre ) && ( $cdavs_p2 -gt $dsthre ) ]]; then
    echo "$hname $ip_addr disk_svc $disk $cdavs_p4,$cdavs_p3,$cdavs_p2,$cdavs_p1,$cdavs" >> $perflog
  fi
  echo "$disk $cdavs" >> $tmp_dir/sarops_p1tmp
done
/usr/bin/cp -f $tmp_dir/sarops_p3 $tmp_dir/sarops_p4
/usr/bin/cp -f $tmp_dir/sarops_p2 $tmp_dir/sarops_p3
/usr/bin/cp -f $tmp_dir/sarops_p1 $tmp_dir/sarops_p2
/usr/bin/cp -f $tmp_dir/sarops_p1tmp $tmp_dir/sarops_p1

### UPTIME
# log a server_rebooted message if the uptime contains min and if the no of min is less than 4
uptmin=$(uptime | awk '{print $3}')
if [[ $(uptime | awk '{print $4}' | grep min) ]]; then
  uptmin=$(uptime | awk '{print $3}')
  if [[ $uptmin -le 4 ]]; then
    uptsec=$(expr $uptmin \* 60)
    timestamp=$(perl -MPOSIX -le "print strftime '%b %d %H%M%S',localtime(time()-$uptsec)")
    /usr/bin/logger -p local5.alert -t AIX_E "$hname $ip_addr $timestamp server_rebooted"
  fi
fi

## log the file to syslog
/usr/bin/logger -p local5.alert -t AIX_P -f $perflog

