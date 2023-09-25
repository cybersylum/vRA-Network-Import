# vRA-Network-Import
A collection of powershell scripts to import local network information into vRA 8.x+

Disclaimer:  This script was obtained from https://github.com/cybersylum
  * You are free to use or modify this code for your own purposes.
  * No warranty or support for this code is provided or implied.  
  * Use this at your own risk.  
  * Testing is highly recommended.

There are 3 scripts

1 - Update-vRA-Networks-IP-Info.ps1 - This will update networks discovered by vRA using information in CSV file (CIDR, DNS,domain, IP Range Start and End)
2 - Update-IP-Ranges.ps1 - This will update or create IP Ranges using the same CSV File.  It will associate any Networks using the same name to the IP Range
3 - Update-Network-Profiles.ps1 - This is still in progress and will be released when ready; but will create Network Profiles based on the discovered Networks


All scripts require Poweshell and PowerVRA 6.x+ - https://github.com/jakkulabs/PowervRA
