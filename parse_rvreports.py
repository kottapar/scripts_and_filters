#!/usr/bin/python

from __future__ import print_function
import csv
import sys

loc = ['DC1', 'DC2', 'DC3']
inputlist = ['vhost.csv', 'vtools.csv', 'vhealth.csv', 'vdatastore.csv', 'vlicense.csv', 'vdisk.csv', 'vinfo.csv', 'vnetw.csv']

for fl in inputlist:
  open(fl, 'w').close()

for fl in inputlist:
  for lc in loc:
    infile = "%s_%s" %(lc,fl)
    outputfile = open(fl, 'a')
    inputfile = open(infile, 'rb')
    reader = csv.DictReader(inputfile, delimiter=',')
    for row in reader:
      if "vhost.csv" in fl:
        ser = row['Service tag']
        if not ser:
          ser = "NA"
        clus = row['Cluster']
        if not clus:
          clus = "Standalone"
        print(lc,row['Host'],clus,row['# CPU'],row['Cores per CPU'],row['# Cores'],row['CPU usage %'],row['# Memory'],row['Memory usage %'],row['# VMs'],row['VMs per Core'],row['# vCPUs'],row['vCPUs per Core'],row['vRAM'],row['VM Used memory'],row['ESX Version'],row['CPU Model'],row['Vendor'],row['Model'],ser,row['BIOS Version'], sep=',', file=outputfile)
      elif "vtools.csv" in fl:
        b = row['Application']
        if not b:
          b = "NA"
        else:
          b = b.replace(',', '')
        print(lc,row['VM'],row['Powerstate'],row['Template'],row['VM Version'],row['Tools'],row['Tools Version'],b, sep=',', file=outputfile)
      elif "vhealth.csv" in fl:
        print(lc,row['Name'],row['Message'], sep=',', file=outputfile)
      elif "vdatastore.csv" in fl:
        hst = row['Hosts']
        hst = hst.replace(', ', ':')
        print(lc,row['Name'],row['# VMs'],row['Capacity MB'],row['Provisioned MB'],row['In Use MB'],row['Free MB'],row['Free %'],row['# Hosts'],hst,row['Version'], sep=',', file=outputfile)
      elif "vdisk.csv" in fl:
        app = row['Application']
        if not app:
          app = "NA"
        else:
          app = app.replace(',', '')
        th = row['Thin']
        if not th:
          th = "NA"
        rp = row['Path']
        rp = rp.split(' ', 1)[0].strip('[]')
        print(lc,row['VM'],row['Disk'],row['Capacity MB'],row['Raw'],row['Disk Mode'],th,app,row['Cluster'],row['Host'],rp, sep=',', file=outputfile)
      elif "vinfo.csv" in fl:
        rp = row['Path']
        rp = rp.split(' ', 1)[0].strip('[]')
        osc=row["OS according to the configuration file"]
        osv=row["OS according to the VMware Tools"]
        if not osc:
          osc = "NA"
        elif not osv:
          osv = "NA"
        if (osc == "NA" and osv == "NA"):
          os = "NA"
        elif osc == "NA":
          os = osv
        elif osv == "NA":
          os = osc
        elif (osc != "NA" and osv != "NA"):
          os = osv
        if ("Linux" in os or "CentOS" in os):
          ostype = "Linux"
        elif "Windows" in os:
          ostype = "Windows"
        else:
          ostype = "Other"
        print(lc,row['VM'],row['CPUs'],row['Memory'],row['Disks'],row['Provisioned MB'],row['In Use MB'],rp,row['Cluster'],row['Host'],osc,osv,os,ostype, sep=',', file=outputfile)
      elif "vnetw.csv" in fl:
        ip = row['IP Address']
        ip = ip.replace(', ', '-')
        print(lc,row['VM'],row['Switch'],row['Connected'],row['Mac Address'],row['Type'],ip, sep=',', file=outputfile)
    inputfile.close
    outputfile.close
