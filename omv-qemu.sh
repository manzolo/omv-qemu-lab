#!/bin/bash
#
# omv-qemu.sh - Script to manage a QEMU VM with OpenMediaVault
# Educational purpose: 1 system disk + 4 storage disks
#

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISKS_DIR="${SCRIPT_DIR}/disks"
ISO_DIR="${SCRIPT_DIR}/iso"

RAM="4G"
CPUS="4"
SYSTEM_DISK_SIZE="32G"
STORAGE_DISK_SIZE="20G"
STORAGE_DISK_COUNT=4

SSH_PORT=2222
WEB_PORT=8080
SAMBA_PORT=4450
FILEBROWSER_PORT=3670

ISO_FILE="${ISO_DIR}/openmediavault.iso"
ISO_URL="https://sourceforge.net/projects/openmediavault/files/latest/download"

SYSTEM_DISK="${DISKS_DIR}/system.qcow2"

# =============================================================================
# COLORS AND FORMATTING
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print_header() {
    echo -e "\n${BLUE}${BOLD}========================================${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}========================================${NC}\n"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local response
    if [[ "$default" == "Y" ]]; then
        echo -en "${YELLOW}${prompt} [Y/n]: ${NC}"
        read -r response
        [[ ! "$response" =~ ^[nN]$ ]]
    else
        echo -en "${YELLOW}${prompt} [y/N]: ${NC}"
        read -r response
        [[ "$response" =~ ^[yY]$ ]]
    fi
}

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

check_deps() {
    print_header "Checking Dependencies"

    local missing=()

    # Check qemu-system-x86_64
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        missing+=("qemu-system-x86_64")
    else
        print_success "qemu-system-x86_64 found"
    fi

    # Check qemu-img
    if ! command -v qemu-img &> /dev/null; then
        missing+=("qemu-img")
    else
        print_success "qemu-img found"
    fi

    # Check wget or curl
    if command -v wget &> /dev/null; then
        print_success "wget found"
    elif command -v curl &> /dev/null; then
        print_success "curl found"
    else
        missing+=("wget or curl")
    fi

    # Check KVM
    if [[ -e /dev/kvm ]]; then
        print_success "KVM available (/dev/kvm exists)"
        if groups | grep -qw kvm; then
            print_success "User in 'kvm' group"
        else
            print_warning "User NOT in 'kvm' group - VM may be slow"
            print_info "Run: sudo usermod -aG kvm \$USER && logout"
        fi
    else
        print_warning "KVM not available - VM will be very slow"
        print_info "Check that virtualization is enabled in BIOS"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        print_error "Missing dependencies: ${missing[*]}"
        echo ""
        print_info "Install with:"
        echo "  sudo apt install qemu-system-x86 qemu-utils wget"
        return 1
    fi

    echo ""
    print_success "All dependencies satisfied!"
    return 0
}

# =============================================================================
# ISO DOWNLOAD
# =============================================================================

download_iso() {
    print_header "Download OpenMediaVault ISO"

    mkdir -p "${ISO_DIR}"

    if [[ -f "${ISO_FILE}" ]]; then
        local size
        size=$(du -h "${ISO_FILE}" | cut -f1)
        print_warning "ISO already present: ${ISO_FILE} (${size})"
        if ! confirm "Do you want to download it again?"; then
            return 0
        fi
        rm -f "${ISO_FILE}"
    fi

    print_info "Downloading from: ${ISO_URL}"
    print_info "Destination: ${ISO_FILE}"
    echo ""

    if command -v wget &> /dev/null; then
        wget --progress=bar:force -O "${ISO_FILE}" "${ISO_URL}"
    elif command -v curl &> /dev/null; then
        curl -L --progress-bar -o "${ISO_FILE}" "${ISO_URL}"
    else
        print_error "No downloader available (wget or curl)"
        return 1
    fi

    if [[ -f "${ISO_FILE}" ]]; then
        local size
        size=$(du -h "${ISO_FILE}" | cut -f1)
        echo ""
        print_success "Download complete! (${size})"
    else
        print_error "Download failed"
        return 1
    fi
}

# =============================================================================
# DISK CREATION
# =============================================================================

create_disks() {
    print_header "Creating Virtual Disks"

    mkdir -p "${DISKS_DIR}"

    # System disk
    if [[ -f "${SYSTEM_DISK}" ]]; then
        print_warning "System disk already exists"
        if ! confirm "Do you want to recreate it? (ALL DATA WILL BE LOST)"; then
            print_info "System disk kept"
        else
            rm -f "${SYSTEM_DISK}"
            print_info "Creating system disk (${SYSTEM_DISK_SIZE})..."
            qemu-img create -f qcow2 "${SYSTEM_DISK}" "${SYSTEM_DISK_SIZE}"
            print_success "System disk created: ${SYSTEM_DISK}"
        fi
    else
        print_info "Creating system disk (${SYSTEM_DISK_SIZE})..."
        qemu-img create -f qcow2 "${SYSTEM_DISK}" "${SYSTEM_DISK_SIZE}"
        print_success "System disk created: ${SYSTEM_DISK}"
    fi

    # Storage disks
    for i in $(seq 1 ${STORAGE_DISK_COUNT}); do
        local disk="${DISKS_DIR}/storage${i}.qcow2"
        if [[ -f "${disk}" ]]; then
            print_warning "Disk storage${i} already exists, skipped"
        else
            print_info "Creating disk storage${i} (${STORAGE_DISK_SIZE})..."
            qemu-img create -f qcow2 "${disk}" "${STORAGE_DISK_SIZE}"
            print_success "Disk storage${i} created"
        fi
    done

    echo ""
    print_success "All disks are ready!"
}

# =============================================================================
# BUILD QEMU COMMAND
# =============================================================================

build_qemu_cmd() {
    local with_iso="$1"
    local boot_cdrom="$2"

    local cmd="qemu-system-x86_64"

    # KVM if available
    if [[ -e /dev/kvm ]]; then
        cmd+=" -enable-kvm"
    fi

    # RAM and CPU
    cmd+=" -m ${RAM}"
    cmd+=" -smp ${CPUS}"

    # System disk
    cmd+=" -drive file=${SYSTEM_DISK},format=qcow2,if=virtio"

    # Storage disks with unique serial numbers for RAID stability
    for i in $(seq 1 ${STORAGE_DISK_COUNT}); do
        local disk="${DISKS_DIR}/storage${i}.qcow2"
        local serial="STORAGE${i}"
        if [[ -f "${disk}" ]]; then
            cmd+=" -drive file=${disk},format=qcow2,if=none,id=disk${i},serial=${serial}"
            cmd+=" -device virtio-blk-pci,drive=disk${i},serial=${serial}"
        elif [[ -f "${disk}.failed" ]]; then
            echo -e "${YELLOW}[WARNING]${NC} Disk storage${i} marked as failed - using empty disk" >&2
            # Use empty disk to maintain device order
            cmd+=" -drive file=${disk}.failed,format=qcow2,if=none,id=disk${i},serial=${serial}"
            cmd+=" -device virtio-blk-pci,drive=disk${i},serial=${serial}"
        fi
    done

    # ISO and boot
    if [[ "$with_iso" == "true" ]]; then
        cmd+=" -cdrom ${ISO_FILE}"
        if [[ "$boot_cdrom" == "true" ]]; then
            cmd+=" -boot d"
        fi
    fi

    # Network with port forwarding
    cmd+=" -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${WEB_PORT}-:80,hostfwd=tcp::${SAMBA_PORT}-:445,hostfwd=tcp::${FILEBROWSER_PORT}-:3670"
    cmd+=" -device virtio-net-pci,netdev=net0"

    # Graphic display
    cmd+=" -display gtk"

    echo "$cmd"
}

# =============================================================================
# START VM INSTALLATION
# =============================================================================

start_install() {
    print_header "OpenMediaVault Installation"

    # Check ISO
    if [[ ! -f "${ISO_FILE}" ]]; then
        print_error "ISO not found: ${ISO_FILE}"
        print_info "Use option 1 to download the ISO"
        return 1
    fi

    # Check system disk
    if [[ ! -f "${SYSTEM_DISK}" ]]; then
        print_error "System disk not found: ${SYSTEM_DISK}"
        print_info "Use option 2 to create disks"
        return 1
    fi

    print_info "Starting VM in installation mode..."
    print_info "VM will boot from CD-ROM"
    echo ""
    print_warning "During installation:"
    echo "  - Select /dev/vda as destination disk"
    echo "  - Disks /dev/vdb, vdc, vdd, vde are for storage"
    echo ""
    print_info "Port forwarding configured:"
    echo "  - SSH:         localhost:${SSH_PORT} -> VM:22"
    echo "  - Web:         localhost:${WEB_PORT} -> VM:80"
    echo "  - Samba:       localhost:${SAMBA_PORT} -> VM:445"
    echo "  - FileBrowser: localhost:${FILEBROWSER_PORT} -> VM:3670"
    echo ""

    local cmd
    cmd=$(build_qemu_cmd "true" "true")

    print_info "QEMU command:"
    echo "  $cmd"
    echo ""

    if confirm "Start VM?" "Y"; then
        eval "$cmd"
    fi
}

# =============================================================================
# START VM NORMAL
# =============================================================================

start_vm() {
    print_header "Starting OpenMediaVault"

    # Check system disk
    if [[ ! -f "${SYSTEM_DISK}" ]]; then
        print_error "System disk not found: ${SYSTEM_DISK}"
        print_info "You need to install OpenMediaVault first"
        return 1
    fi

    print_info "Starting VM..."
    echo ""
    print_info "Access after boot:"
    echo "  - SSH:         ssh -p ${SSH_PORT} root@localhost"
    echo "  - Web:         http://localhost:${WEB_PORT}"
    echo "                 (user: admin, password: openmediavault)"
    echo "  - Samba:       smbclient -p ${SAMBA_PORT} -L localhost -U admin"
    echo "  - FileBrowser: http://localhost:${FILEBROWSER_PORT}"
    echo ""

    local cmd
    cmd=$(build_qemu_cmd "false" "false")

    print_info "QEMU command:"
    echo "  $cmd"
    echo ""

    if confirm "Start VM?" "Y"; then
        eval "$cmd"
    fi
}

# =============================================================================
# STATUS
# =============================================================================

show_status() {
    print_header "System Status"

    # ISO
    echo -e "${BOLD}ISO:${NC}"
    if [[ -f "${ISO_FILE}" ]]; then
        local iso_size
        iso_size=$(du -h "${ISO_FILE}" | cut -f1)
        print_success "openmediavault.iso (${iso_size})"
    else
        print_warning "ISO not present"
    fi
    echo ""

    # Disks
    echo -e "${BOLD}Virtual disks:${NC}"
    if [[ -d "${DISKS_DIR}" ]]; then
        for disk in "${DISKS_DIR}"/*.qcow2; do
            if [[ -f "$disk" ]]; then
                local name
                name=$(basename "$disk")
                local info
                info=$(qemu-img info "$disk" 2>/dev/null | grep -E "virtual size|disk size" | tr '\n' ' ')
                print_success "${name}: ${info}"
            fi
        done

        # Show failed disks
        for disk in "${DISKS_DIR}"/*.qcow2.backup; do
            if [[ -f "$disk" ]]; then
                local name
                name=$(basename "$disk" .backup)
                print_error "${name}: FAILED (simulated, backup available)"
            fi
        done

        local count
        count=$(find "${DISKS_DIR}" -name "*.qcow2" 2>/dev/null | wc -l)
        local failed_count
        failed_count=$(find "${DISKS_DIR}" -name "*.qcow2.backup" 2>/dev/null | wc -l)
        if [[ "$count" -eq 0 ]] && [[ "$failed_count" -eq 0 ]]; then
            print_warning "No disks created"
        fi
    else
        print_warning "Disks directory does not exist"
    fi
    echo ""

    # Configuration
    echo -e "${BOLD}VM Configuration:${NC}"
    echo "  RAM:              ${RAM}"
    echo "  CPU:              ${CPUS} cores"
    echo "  SSH port:         ${SSH_PORT}"
    echo "  Web port:         ${WEB_PORT}"
    echo "  Samba port:       ${SAMBA_PORT}"
    echo "  FileBrowser port: ${FILEBROWSER_PORT}"
    echo ""

    # KVM
    echo -e "${BOLD}KVM:${NC}"
    if [[ -e /dev/kvm ]]; then
        print_success "Available"
    else
        print_warning "Not available (VM will be slow)"
    fi
}

# =============================================================================
# SIMULATE DISK FAILURE
# =============================================================================

simulate_disk_failure() {
    print_header "Simulate Disk Failure"

    print_warning "This function simulates a disk failure for educational purposes."
    print_info "The original disk will be backed up and replaced with an empty one"
    echo ""

    # Show available disks
    echo -e "${BOLD}Available storage disks:${NC}"
    local available=()
    for i in $(seq 1 ${STORAGE_DISK_COUNT}); do
        local disk="${DISKS_DIR}/storage${i}.qcow2"
        if [[ -f "${disk}" ]] && [[ ! -f "${disk}.backup" ]]; then
            local info
            info=$(qemu-img info "$disk" 2>/dev/null | grep "virtual size" | awk '{print $3}')
            echo "  ${i}. storage${i}.qcow2 (${info})"
            available+=("$i")
        elif [[ -f "${disk}.backup" ]]; then
            echo -e "  ${i}. storage${i}.qcow2 ${RED}[ALREADY FAILED]${NC}"
        else
            echo -e "  ${i}. storage${i}.qcow2 ${YELLOW}[DOES NOT EXIST]${NC}"
        fi
    done
    echo ""

    if [[ ${#available[@]} -eq 0 ]]; then
        print_error "No disk available to mark as failed"
        return 1
    fi

    echo -en "${CYAN}Select disk to 'fail' [1-${STORAGE_DISK_COUNT}] (0 to cancel): ${NC}"
    read -r disk_num

    if [[ "$disk_num" == "0" ]]; then
        print_info "Operation cancelled"
        return 0
    fi

    if [[ ! "$disk_num" =~ ^[1-9][0-9]*$ ]] || [[ "$disk_num" -gt "$STORAGE_DISK_COUNT" ]]; then
        print_error "Invalid selection"
        return 1
    fi

    local disk="${DISKS_DIR}/storage${disk_num}.qcow2"

    if [[ ! -f "${disk}" ]] || [[ -f "${disk}.backup" ]]; then
        print_error "Disk storage${disk_num} does not exist or is already failed"
        return 1
    fi

    if confirm "Confirm you want to simulate failure of storage${disk_num}?"; then
        # Backup original disk and create empty replacement
        mv "${disk}" "${disk}.backup"
        qemu-img create -f qcow2 "${disk}.failed" "${STORAGE_DISK_SIZE}" >/dev/null
        echo ""
        print_success "Disk storage${disk_num} marked as failed!"
        print_info "Original disk backed up to: storage${disk_num}.qcow2.backup"
        print_info "Empty disk created: storage${disk_num}.qcow2.failed"
        echo ""
        print_info "Next steps:"
        echo "  1. Start VM (option 4) - RAID will be in degraded state"
        echo "  2. In OMV you will see the RAID degraded with a missing disk"
        echo "  3. Use option 8 to 'replace' the failed disk"
    fi
}

# =============================================================================
# REPLACE FAILED DISK
# =============================================================================

replace_failed_disk() {
    print_header "Replace Failed Disk"

    # Show failed disks
    echo -e "${BOLD}Failed disks:${NC}"
    local failed=()
    for i in $(seq 1 ${STORAGE_DISK_COUNT}); do
        local disk="${DISKS_DIR}/storage${i}.qcow2"
        if [[ -f "${disk}.backup" ]]; then
            local info
            info=$(qemu-img info "${disk}.backup" 2>/dev/null | grep "virtual size" | awk '{print $3}')
            echo "  ${i}. storage${i} (${info}) - original backed up"
            failed+=("$i")
        fi
    done
    echo ""

    if [[ ${#failed[@]} -eq 0 ]]; then
        print_info "No failed disk found"
        return 0
    fi

    echo -e "${BOLD}Options:${NC}"
    echo "  1. Restore original disk (simulate repair - data preserved)"
    echo "  2. Create new empty disk (simulate replacement - rebuild RAID)"
    echo "  0. Cancel"
    echo ""

    echo -en "${CYAN}Select option: ${NC}"
    read -r option

    case "$option" in
        0)
            print_info "Operation cancelled"
            return 0
            ;;
        1|2)
            echo ""
            echo -en "${CYAN}Select disk to restore/replace [1-${STORAGE_DISK_COUNT}]: ${NC}"
            read -r disk_num

            if [[ ! "$disk_num" =~ ^[1-9][0-9]*$ ]] || [[ "$disk_num" -gt "$STORAGE_DISK_COUNT" ]]; then
                print_error "Invalid selection"
                return 1
            fi

            local disk="${DISKS_DIR}/storage${disk_num}.qcow2"

            if [[ ! -f "${disk}.backup" ]]; then
                print_error "Disk storage${disk_num} is not marked as failed"
                return 1
            fi

            if [[ "$option" == "1" ]]; then
                # Restore original disk
                rm -f "${disk}.failed"
                mv "${disk}.backup" "${disk}"
                echo ""
                print_success "Disk storage${disk_num} restored with original data!"
                print_info "RAID should automatically resync on next boot"
            else
                # Create new disk
                rm -f "${disk}.failed"
                rm -f "${disk}.backup"
                print_info "Creating new disk storage${disk_num} (${STORAGE_DISK_SIZE})..."
                qemu-img create -f qcow2 "${disk}" "${STORAGE_DISK_SIZE}"
                echo ""
                print_success "New disk storage${disk_num} created!"
                print_info "The new disk is empty and must be added to RAID in OMV"
            fi

            echo ""
            print_info "Next steps:"
            echo "  1. Start VM (option 4)"
            echo "  2. In OMV, go to Storage → RAID Management"
            echo "  3. The RAID should rebuild automatically or add the disk manually"
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup() {
    print_header "System Reset"

    print_warning "This operation will delete ALL virtual disks!"
    print_warning "OpenMediaVault installation will be lost."
    echo ""

    if ! confirm "Are you sure you want to proceed?"; then
        print_info "Operation cancelled"
        return 0
    fi

    if ! confirm "Do you DEFINITELY confirm?"; then
        print_info "Operation cancelled"
        return 0
    fi

    print_info "Deleting disks..."

    if [[ -d "${DISKS_DIR}" ]]; then
        rm -f "${DISKS_DIR}"/*.qcow2
        rm -f "${DISKS_DIR}"/*.qcow2.failed
        rm -f "${DISKS_DIR}"/*.qcow2.backup
        print_success "Disks deleted"
    fi

    echo ""
    print_success "Reset complete!"
    print_info "Use option 2 to recreate disks"
}

# =============================================================================
# MAIN MENU
# =============================================================================

show_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   OpenMediaVault QEMU Manager          ║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  1. Download ISO                       ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  2. Create disks                       ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  3. Install OMV (boot from ISO)        ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  4. Start VM                           ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  5. Status                             ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  6. Reset (delete disks)               ${BOLD}║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  7. Simulate disk failure              ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  8. Replace failed disk                ${BOLD}║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  9. Exit                               ${BOLD}║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    # Check dependencies at startup
    if ! check_deps; then
        exit 1
    fi

    while true; do
        show_menu
        echo -en "${CYAN}Select an option [1-9]: ${NC}"
        read -r choice

        case "$choice" in
            1) download_iso ;;
            2) create_disks ;;
            3) start_install ;;
            4) start_vm ;;
            5) show_status ;;
            6) cleanup ;;
            7) simulate_disk_failure ;;
            8) replace_failed_disk ;;
            9)
                echo ""
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac

        echo ""
        echo -en "${CYAN}Press ENTER to continue...${NC}"
        read -r
    done
}

# Run
main "$@"
