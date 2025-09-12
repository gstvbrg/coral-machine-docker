# Tailscale SSH Setup for Coral Machine

## Overview
Your container now has a **persistent Tailscale identity** that survives pod restarts and GPU changes. Connect via the stable hostname `coral-machine` from anywhere on your tailnet.

## Initial Setup (One-Time)

### 1. Get Tailscale Auth Key
1. Go to: https://login.tailscale.com/admin/settings/keys
2. Generate a **reusable** auth key (important!)
3. Optional: Disable key expiry for long-lived containers

### 2. Configure RunPod Environment
Add environment variable in RunPod:
```
TAILSCALE_AUTHKEY=tskey-auth-xxxxx-xxxxxxxxx
```

**Alternative: Use file-based auth (more secure)**
```bash
# In RunPod terminal after first start
echo "tskey-auth-xxxxx-xxxxxxxxx" > /workspace/deps/runtime/tailscale/authkey
```

### 3. Start/Restart Pod
The container will automatically:
- Start Tailscale daemon
- Authenticate using your key (first time only)
- Enable Tailscale SSH
- Persist identity to `/workspace/deps/runtime/tailscale/`

## Connecting via SSH

### From Cursor/VS Code
1. Install Tailscale on your local machine
2. Add to your SSH config (`~/.ssh/config` or `C:\Users\gusta\.ssh\config`):

```ssh
Host coral-machine
    HostName coral-machine
    User root
    # No port needed - Tailscale handles it
    # No IP needed - MagicDNS resolves it
    # No keys needed - Tailscale handles auth
    ForwardAgent yes
    LocalForward 11111 localhost:11111  # ParaView
```

3. Connect in Cursor:
   - Ctrl+Shift+P → "Remote-SSH: Connect to Host"
   - Select "coral-machine"
   - Done! Works regardless of pod IP/ID

### From Terminal
```bash
# Direct Tailscale SSH (no SSH keys needed!)
tailscale ssh root@coral-machine

# Or with port forwarding for ParaView
tailscale ssh root@coral-machine -L 11111:localhost:11111

# Traditional SSH (if you prefer)
ssh root@coral-machine
```

## How It Works

1. **Persistent Identity**: Machine state stored in `/workspace/deps/runtime/tailscale/tailscaled.state`
2. **Stable Hostname**: Always `coral-machine.tail*.ts.net` 
3. **Auto-Recovery**: If pod restarts, Tailscale reconnects with same identity
4. **Zero Trust**: Only devices on your tailnet can connect
5. **No Public Exposure**: Unlike ngrok, completely private

## Troubleshooting

### Check Tailscale Status
```bash
# In container terminal
tailscale status
tailscale ip -4  # Get Tailscale IP
```

### View Logs
```bash
tail -f /workspace/deps/runtime/tailscale/tailscaled.log
```

### Manual Authentication (if auto-auth fails)
```bash
tailscale up --authkey=tskey-auth-xxxxx-xxxxxxxxx --ssh --hostname=coral-machine
```

### Reset Identity (if needed)
```bash
# Warning: This creates a new machine identity
rm /workspace/deps/runtime/tailscale/tailscaled.state
# Then restart the pod
```

## Network Requirements

RunPod must allow:
- **Outbound**: UDP 41641 (Tailscale's DERP relay)
- **Outbound**: HTTPS 443 (control plane)
- **/dev/net/tun**: Required for VPN (usually available)

## Benefits Over Other Solutions

| Feature | Tailscale | RunPod SSH | ngrok | Regular SSH |
|---------|-----------|------------|-------|-------------|
| Stable hostname | ✅ coral-machine | ❌ Changes | ❌ Changes (free) | ❌ IP changes |
| Private/Secure | ✅ Zero trust | ✅ Private | ❌ Public | ✅ Private |
| No SSH keys | ✅ Tailscale auth | ❌ Need keys | ❌ Need keys | ❌ Need keys |
| Survives restarts | ✅ Persistent | ❌ New ID | ❌ New URL | ❌ New IP |
| Direct connection | ✅ P2P when possible | ✅ Direct | ❌ Relay only | ✅ Direct |
| Free | ✅ Personal use | ✅ Included | ❌ Paid for stable | ✅ Free |

## Security Notes

- Auth keys are only used for initial registration
- After registration, the machine identity is cryptographically secured
- Each container has its own unique machine identity
- Access controlled via Tailscale ACLs (admin panel)
- No passwords or SSH keys to manage

## ACL Configuration (Important!)

Tailscale SSH requires proper ACL configuration in your admin panel:

1. **Default Policy**: By default, only the machine owner can SSH
2. **Custom ACLs**: Add SSH rules to https://login.tailscale.com/admin/acls
   ```json
   "ssh": [
     {
       "action": "accept",
       "src": ["autogroup:owner"],
       "dst": ["tag:coral-machine"],
       "users": ["root", "autogroup:nonroot"]
     }
   ]
   ```
3. **Check Mode**: For production, enable periodic re-authentication:
   ```json
   "ssh": [
     {
       "action": "check",
       "src": ["autogroup:owner"],
       "dst": ["tag:prod"],
       "users": ["root"],
       "checkPeriod": "12h"
     }
   ]
   ```

## Implementation Notes

- **Port 22**: Tailscale SSH only works on port 22 internally
- **No conflict**: RunPod setup runs custom SSH on port 2222 to avoid conflicts
- **Modern method**: Uses `tailscale set --ssh` (recommended over `tailscale up --ssh`)