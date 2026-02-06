# OpenMediaVault QEMU Lab

An educational environment for learning NAS administration, RAID management, and disk failure recovery using OpenMediaVault in a QEMU virtual machine.

## Overview

This project provides a complete lab environment to:

- Install and configure OpenMediaVault (a Debian-based NAS solution)
- Create and manage RAID arrays
- Configure Samba/SMB file sharing
- **Simulate disk failures** and practice RAID recovery procedures
- Learn storage management in a safe, isolated environment

## Features

- Automated VM setup with QEMU/KVM
- 1 system disk + 4 storage disks for RAID experiments
- Port forwarding for SSH, Web UI, Samba, and FileBrowser
- Disk failure simulation for educational purposes
- Interactive menu-driven interface

## Requirements

- Linux (Ubuntu/Debian recommended)
- QEMU with KVM support
- At least 8GB RAM (4GB for VM + host)
- ~100GB free disk space

### Install Dependencies

```bash
sudo apt install qemu-system-x86 qemu-utils wget
```

### Enable KVM (recommended for performance)

```bash
sudo usermod -aG kvm $USER
# Logout and login again
```

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/manzolo/omv-qemu-lab.git
cd omv-qemu-lab
```

### 2. Run the script

```bash
chmod +x omv-qemu.sh
./omv-qemu.sh
```

### 3. Initial Setup

Follow the menu options in order:

1. **Download ISO** - Downloads the latest OpenMediaVault ISO
2. **Create disks** - Creates virtual disks (1 system + 4 storage)
3. **Install OMV** - Boots from ISO to install OpenMediaVault
   - Select `/dev/vda` as the installation target
   - Complete the Debian installer
4. **Start VM** - Boots the installed system

## Accessing OpenMediaVault

After the VM is running:

| Service     | URL/Command                                      | Credentials                    |
|-------------|--------------------------------------------------|--------------------------------|
| Web UI      | http://localhost:8080                            | admin / openmediavault         |
| SSH         | `ssh -p 2222 root@localhost`                     | (set during installation)      |
| Samba       | `smbclient -p 4450 -L localhost -U username`     | (configured in OMV)            |
| FileBrowser | http://localhost:3670                            | (after installing plugin)      |

## Lab Exercises

### Exercise 1: Create a RAID Array

1. Access OMV Web UI at http://localhost:8080
2. Go to **Storage → Disks** - you should see vdb, vdc, vdd, vde
3. Go to **Storage → RAID Management**
4. Create a new RAID array:
   - RAID 1 (mirror): Select 2 disks
   - RAID 5: Select 3+ disks
   - RAID 6: Select 4 disks
5. Go to **Storage → File Systems**
6. Create a filesystem on the RAID device
7. Mount the filesystem

### Exercise 2: Configure Samba Share

1. Go to **Services → SMB/CIFS → Settings**
2. Enable the service
3. Go to **Services → SMB/CIFS → Shares**
4. Add a new share pointing to your mounted filesystem
5. Configure user access in **Users → Users**
6. Apply changes

Test from host:
```bash
# List shares
smbclient -p 4450 -L localhost -U username

# Mount share
sudo mount -t cifs //127.0.0.1/sharename /mnt -o port=4450,username=user,vers=3.0,sec=ntlmssp
```

### Exercise 3: Simulate Disk Failure and Recovery

This is the key educational feature of this lab.

#### Step 1: Simulate a disk failure

1. Shutdown the VM
2. Run `./omv-qemu.sh` and select option **7. Simulate disk failure**
3. Choose which storage disk to "fail"
4. Start the VM with option **4**

#### Step 2: Observe degraded RAID

1. Access OMV Web UI
2. Go to **Storage → RAID Management**
3. Notice the RAID is now in **degraded** state
4. Check the dashboard for warnings

#### Step 3: Replace the failed disk

1. Shutdown the VM
2. Run `./omv-qemu.sh` and select option **8. Replace failed disk**
3. Choose option **2** to create a new empty disk (simulates hardware replacement)
4. Start the VM

#### Step 4: Rebuild the RAID

1. Access OMV Web UI
2. Go to **Storage → RAID Management**
3. Select your degraded RAID array
4. Click **Recover** and select the new disk
5. Watch the rebuild progress

## Configuration

Default settings in `omv-qemu.sh`:

```bash
RAM="4G"                    # VM memory
CPUS="4"                    # CPU cores
SYSTEM_DISK_SIZE="32G"      # System disk size
STORAGE_DISK_SIZE="20G"     # Each storage disk size
STORAGE_DISK_COUNT=4        # Number of storage disks

SSH_PORT=2222               # Host port for SSH
WEB_PORT=8080               # Host port for Web UI
SAMBA_PORT=4450             # Host port for Samba
FILEBROWSER_PORT=3670       # Host port for FileBrowser
```

## Menu Options

```
╔════════════════════════════════════════╗
║   OpenMediaVault QEMU Manager          ║
╠════════════════════════════════════════╣
║  1. Download ISO                       ║
║  2. Create disks                       ║
║  3. Install OMV (boot from ISO)        ║
║  4. Start VM                           ║
║  5. Status                             ║
║  6. Reset (delete disks)               ║
╠════════════════════════════════════════╣
║  7. Simulate disk failure              ║
║  8. Replace failed disk                ║
╠════════════════════════════════════════╣
║  9. Exit                               ║
╚════════════════════════════════════════╝
```

## Directory Structure

```
omv-qemu-lab/
├── omv-qemu.sh          # Main script
├── README.md            # This file
├── disks/               # Virtual disks (created by script)
│   ├── system.qcow2     # System disk
│   ├── storage1.qcow2   # Storage disk 1
│   ├── storage2.qcow2   # Storage disk 2
│   ├── storage3.qcow2   # Storage disk 3
│   └── storage4.qcow2   # Storage disk 4
└── iso/                 # ISO files (created by script)
    └── openmediavault.iso
```

## Troubleshooting

### VM is very slow

- Ensure KVM is enabled: `ls -la /dev/kvm`
- Add user to kvm group: `sudo usermod -aG kvm $USER`
- Logout and login again

### Cannot mount Samba share

Use the correct mount options:
```bash
sudo mount -t cifs //127.0.0.1/share /mnt -o port=4450,username=user,vers=3.0,sec=ntlmssp
```

### QEMU display issues

If GTK display doesn't work, edit the script and change:
```bash
cmd+=" -display gtk"
```
to:
```bash
cmd+=" -display sdl"
# or
cmd+=" -vnc :0"  # then connect with VNC client to localhost:5900
```

## License

MIT License - Feel free to use this for educational purposes.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Acknowledgments

- [OpenMediaVault](https://www.openmediavault.org/) - The excellent NAS solution
- [QEMU](https://www.qemu.org/) - The powerful machine emulator
