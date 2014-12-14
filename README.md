audit-ec2reservations
=====================

Powershell script to (approximately) match your EC2 reservations with your EC2 instances

# Prerequisites

* AWS PowerShell CMDLets
* PowerShell 4.0+
* Valid credentials configured using Set-AWSCredentials

# About
This script works by inferring the Product Type of your EC2 instances from their AMI descriptions.  
If it cannot find the AMI by using Get-EC2Image, it will try to scrape it from thecloudmarket.com.  
I didn't want to unnecessarily hammer thecloudmarket.com so it also includes a form of caching for known AMI IDs.  
So long as you don't delete or move knownAMIs.json, it should only ever scrape thecloudmarket.com once.

# Troubleshooting
If your EC2 instance was created from a private AMI that no longer exists, it will appear at the end as an instance that could not be matched.
You can use the information provided in this section of the script to figure out what the product is based on your own knowledge of the system, and then populate knownAMIs.json with the AMI and ImageType.
Bear in mind that ImageType must match the reservation type listed from Get-EC2ReservedInstance exactly! 
