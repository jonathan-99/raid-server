# Raspberry Pi RAID Orchestration

This project provides an automated way to configure RAID 1 arrays across multiple Raspberry Pi devices from a jumpbox. It handles prerequisites, firewall configuration, RAID creation with `mdadm`, and per-device logging.  

The orchestrator supports **simultaneous installations**, aggregated summaries, and optional USB device queries.  

---

## Directory Structure

raid-server/
├── install_raid_orchestration.sh # Multi-target orchestrator
├── ssh_setup.sh # Helper script to ensure passwordless SSH
├── install-raid-server.sh # Script executed on each Raspberry Pi target
└── logs/ # Automatically created; stores per-device logs and summary

---

## Prerequisites

- Jumpbox running Linux (e.g., Ubuntu, Debian, Raspbian)
- SSH access to target Raspberry Pi devices
- Bash shell
- `scp` and `ssh` installed on jumpbox
- Target Raspberry Pi OS (Debian/Raspbian-based)

> **Optional**: Configure passwordless SSH for smoother automation. The orchestrator will prompt for passwords if not configured.

---

## Setup

1. **Clone the repository to your jumpbox:**

```bash
git clone <your-repo-url> raid-server
cd raid-server```

2. **Make scripts executable:**
```chmod +x install_raid_orchestration.sh ssh_setup.sh install-raid-server.sh```

3. **Ensure logs/ directory exists:**
```mkdir -p logs```

## Usage
1. Install RAID on one or more Raspberry Pi targets
```./install_raid_orchestration.sh <IP1> <IP2> ... [options]```


This will:

Verify SSH access via ssh_setup.sh

Copy install-raid-server.sh to each target

Execute the RAID installation

Log output per device to logs/<hostname>_install.log

Generate an aggregated summary table at the end

2. **List USB disks on a single target**
```./install_raid_orchestration.sh 192.168.3.101 --return-usb-devices```

Options.
| Option                 | Description                                  | Default |
| ---------------------- | -------------------------------------------- | ------- |
| `--user <user>`        | SSH username                                 | `pi`    |
| `--port <port>`        | SSH port                                     | `22`    |
| `--max-parallel <n>`   | Maximum concurrent installations             | `3`     |
| `--return-usb-devices` | Print connected USB disks on a single target | N/A     |
| `--help`               | Show help message                            | N/A     |

