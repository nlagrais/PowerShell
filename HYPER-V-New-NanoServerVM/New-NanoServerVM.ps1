﻿<#
.SYNOPSIS
	This script create a VHDX with the Nano Server image, add a new VM on the Hyper-V host and attach the VHDX to this VM

.DESCRIPTION
    Copy the NanoServerGenerator from a Windows Server 2016 ISO to a local folder, then, creation of a VHDX with the image of NanoServer and add a VM in the Hyper-V Host. 
    The VM used the VHDX created by NanoServerGenerator and will be connected to the virtual network specified. By default, the VM will have "512 Mb" of RAM.

.PARAMETER ISOPath
    The path to the ISO file of Windows Server 2016, to get NanoServerGenerator

.PARAMETER NanoModulePath
    The destination path to copy the NanoServerGenerator folder which contains the module NanoServerImageGenerator

.PARAMETER VHDXPath
    The path where you want to store the VHDX file for the new NanoServer VM

.PARAMETER VMName
    Name of the VM on Hyper-V

.PARAMETER Password
    Password of the "Adminisitrator" account in Nano Server, for this new VM

.PARAMETER VMvSwitch
    Name of the virtual network (vSwitch) that you want to use to connect this VM on the network. It must be already exist

.PARAMETER VMPowerOn
    Boolean to define if you want that the VM start or not after the creation. By default, the VM will start

.PARAMETER VMPackage
    List of one or multiple package that you want to include in the NanoServer image, such as "Microsoft-NanoServer-DSC-Package" or "Microsoft-NanoServer-DNS-Package"
    You must separate the package name by comma, for example : "Microsoft-NanoServer-DSC-Package,Microsoft-NanoServer-DNS-Package"

.EXAMPLE
.\New-NanoServerVM.ps1 -ISOPath "V:\ISO\WS2016.ISO" -NanoModulePath "V:\NANO" -VHDXPath "V:\VM\VHDX" -VMName "NanoServer-02" -password (ConvertTo-SecureString -AsPlainText -Force "P@ssWoRd") -VMvSwitch "LAN" -VMPowerOn $false
	This will run the script for create a VM named "NanoServer-02", with the password "P@ssWoRd" for the account Administrator, connected to the vSwitch "LAN" but the VM will not start after creation. For this, we use the ISO ""V:\ISO\WS2016.ISO", we copy NanoServerGenerator to "V:\NANO" and we store the VHDX in "V:\VM\VHDX".

.INPUTS

.OUTPUTS
	
.NOTES
	NAME:	New-NanoServerVM.ps1
	AUTHOR:	Florian Burnel
	EMAIL:	florian.burnel@it-connect.fr
	WWW:	www.it-connect.fr
	Twitter:@FlorianBurnel

	REQUIREMENTS:
		-Windows Server 2016 ISO
        -Hyper-V Host

	VERSION HISTORY:

	1.0 	2016.10.28
		    Initial Version

    1.1     2016.11.14
            Bug fix on the path to the module NanoServer
            Add the possibility to install one or multiple NanoServer packages into the image directly
            Add different output in the console during the execution

    TODO
            Secure Password integration
#>

PARAM(
    [Parameter(Mandatory = $true, HelpMessage = "You must specify a path for the Windows Server 2016 ISO")]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ISOPath,

    [Parameter(Mandatory = $true, HelpMessage = "You must specify a destination path for the 'Nano Server Generator' module")]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$NanoModulePath,

    [Parameter(Mandatory = $true, HelpMessage = "You must specify a path to store the VHDX (Virtual Disk)")]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$VHDXPath,

    [Parameter(Mandatory = $true, HelpMessage = "You must specify a name for the virtual machine")]
    [ValidateScript({ !(Get-VM -Name $_) })]
    [string]$VMName,

    [Parameter(Mandatory = $true, HelpMessage = "You must specify a password for the Administrator account")]
    [Security.SecureString]$Password,

    [Parameter(Mandatory = $true, HelpMessage = "You must specify a name for the vSwitch on which you want connect the VM")]
    [ValidateScript({ Get-VMSwitch -Name $_ })]
    [string]$VMvSwitch,

    [Parameter(Mandatory = $false, HelpMessage = "You must specify a valid name for the package")]
    [ValidatePattern("Microsoft-NanoServer-[a-z]*-Package")]
    [string]$VMPackage,

    [boolean]$VMPowerOn = $true
)
 

# Mount ISO
$MountISO = Mount-DiskImage -ImagePath $ISOPath -StorageType ISO -PassThru

# Get the drive letter of the volume where the ISO is mounted
$LetterISO = ($MountISO | Get-Volume).DriveLetter

# Copy the folder NanoServerImageGenerator
# Source Example : E:\NanoServer\NanoServerImageGenerator
if(!(Test-Path "$NanoModulePath\NanoServerImageGenerator")){
    $SourcePath = $LetterISO + ":\NanoServer\NanoServerImageGenerator" 
    Copy-Item -Path $SourcePath -Destination $NanoModulePath -Recurse 
}

# Import NanoServerImageGenerator module
Import-Module "$NanoModulePath\NanoServerImageGenerator\NanoServerImageGenerator.psd1" -Verbose

$MediaPath = $LetterISO + ":\"

if($VMPackage -ne ""){

    Write-Host "Generation of the NanoServer image..." -ForegroundColor Green
    New-NanoServerImage -Edition Standard -DeploymentType Guest -MediaPath $MediaPath -TargetPath "$VHDXPath\$VMName.vhdx" -ComputerName $VMName -AdministratorPassword $Password -Package $VMPackage.Split(",")
    # Note 1 : .vhd create a VM Gen 1, .vhdx create a VM Gen 2
    # Note 2 : New-NanoServerImage is supported on Windows 8.1, Windows 10, Windows Server 2012 R2, and Windows Server 2016.

}else{

    Write-Host "Generation of the NanoServer image..." -ForegroundColor Green
    New-NanoServerImage -Edition Standard -DeploymentType Guest -MediaPath $MediaPath -TargetPath "$VHDXPath\$VMName.vhdx" -ComputerName $VMName -AdministratorPassword $Password

} # if($VMPackage -ne "")

# Only if the VHDX exist, create the VM
if(Test-Path "$VHDXPath\$VMName.vhdx"){

    Write-Host "VHDX found ! The VM will be create !" -ForegroundColor Green

    # Create a new VM and attach our new VHDX generated by NanoServerGenerator
    New-VM -Name $VMName -SwitchName $VMvSwitch -VHDPath "$VHDXPath\$VMName.vhdx" -Generation 2 -MemoryStartupBytes 512MB -BootDevice VHD

    # Start the VM if $VMPowerOn is $true and if the VM exist only
    if(($VMPowerOn -eq $true) -and (Get-VM $VMName)){
        Start-VM $VMName
    }

    # Add the Nano Server host the TrustedHosts list of WinRM
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$VMName" -Force
}else{

    Write-Host "VHDX not found ! Impossible to create the VM, check the VHDX creation before !" -ForegroundColor Red

} # if(Test-Path "$VHDXPath\$VMName.vhdx") 

# Dismount ISO
Dismount-DiskImage -ImagePath $ISOPath