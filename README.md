<div align="center">
  <img src="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png" height="120px" alt="Proxmox VE Helper-Scripts Logo" />

  <h1>Proxmox VE Helper-Scripts (Offline Fork)</h1>
  <p><em>A Community Legacy in Memory of @tteck</em></p>
  <p>
    <strong>Offline-capable fork</strong> of
    <a href="https://github.com/community-scripts/ProxmoxVE">community-scripts/ProxmoxVE</a>
  </p>
  <p>This fork has been modified for <strong>local/offline operation</strong>:</p>
  <div align="left" style="display: inline-block;">
    • All scripts source from local files (no remote curl|bash)<br />
    • Interactive script discovery via <code>run.sh</code><br />
    • Works on air-gapped networks<br />
    • Auditable local code
  </div>
</div>

---

## Getting Started

1. **Clone to Proxmox host**
   ```bash
   git clone https://github.com/fmcglinn/ProxmoxVE.git /opt/community-scripts
   ```

2. **Install dependencies**
   ```bash
   apt install jq whiptail
   ```

3. **Add to PATH** (optional)
   ```bash
   ln -sf /opt/community-scripts/run.sh /usr/local/bin/community-scripts
   ```

4. **Run interactive launcher**
   ```bash
   community-scripts
   ```
   Or if you skipped step 3: `cd /opt/community-scripts && ./run.sh`

5. Browse categories, search scripts, and install directly from local files.

### Direct Script Execution

```bash
cd /opt/community-scripts
bash ct/plex.sh
```

---

## Requirements

| Requirement | Details |
|-------------|---------|
| Proxmox VE | 8.4.x / 9.0.x / 9.1.x |
| OS | Debian-based with Proxmox Tools |
| Network | Offline capable (after initial clone) |
| Dependencies | `jq`, `whiptail` |

---

## Key Features

- **Quick Setup** - One-command installations for popular services
- **Flexible Config** - Simple mode for beginners, advanced options for power users
- **Auto Updates** - Built-in update mechanisms for installed services
- **400+ Scripts** - LXC containers and VMs for popular self-hosted apps

---

## Attribution

Originally created by **tteck**, now maintained by the community.

Upstream project: [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)

---

## License

MIT License - see [LICENSE](LICENSE)
