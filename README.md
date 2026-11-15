# Rocky Linux 9 XRDP Setup

`setup-rocky9-xrdp.sh` turns a Rocky Linux 9 server into a graphical workstation that you can access over RDP. It updates the system, installs the Workstation desktop, configures graphical boot and GNOME to use X11, then installs and starts `xrdp` and its Xorg integration. The setup reboots once and continues automatically after startup. If `firewalld` is active, it opens TCP port 3389.
BONUS: Now also installs vscode :)

The supplied [`cloud-config.yaml`](cloud-config.yaml) creates the `rocky` and `rockyadmin` administrator accounts and enables and starts `sshd`. It also allows SSH through `firewalld` when it is active.

## Run

Log in to the Rocky server with an account that has administrator privileges. If you used the supplied cloud-init file, log in as `rocky` or `rockyadmin`:

```bash
ssh rocky@<ROCKY_SERVER_IP>
```

Then download and run the script (if no curl in your image/vm install it first or scp it in from your workstation!):

```bash
curl -L https://raw.githubusercontent.com/hardevsanghera/xrdpOnRocky9/main/setup-rocky9-xrdp.sh \
  -o setup-rocky9-xrdp.sh
```

The script uses `sudo` when needed. After it completes, connect your RDP client to the server on TCP port 3389. Make sure your cloud firewall or security group also permits RDP access from the intended client.
